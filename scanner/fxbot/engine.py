"""One trading cycle: scan -> snapshot -> Claude -> risk checks -> orders -> journal."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from fxscan.scan import load_universe, scan
from fxscan.universe import ALL_SYMBOLS

from .config import Config
from .models import Decision
from .risk import RiskManager, position_risk

ROOT = Path(__file__).resolve().parent.parent


class Engine:
    def __init__(self, cfg: Config, broker, brain, dry_run: bool = False, log=print):
        self.cfg, self.broker, self.brain, self.dry_run, self.log = cfg, broker, brain, dry_run, log
        self.risk = RiskManager(cfg)
        self.dir = Path(cfg.state_dir)
        if not self.dir.is_absolute():
            self.dir = ROOT / self.dir
        self.dir.mkdir(parents=True, exist_ok=True)
        self.symbols = ([s.strip().upper() for s in cfg.symbols.split(",") if s.strip()]
                        or list(ALL_SYMBOLS))

    # -- state and journal -----------------------------------------------------------------
    @property
    def state_file(self) -> Path:
        return self.dir / "state.json"

    def load_state(self) -> dict:
        if self.state_file.exists():
            return json.loads(self.state_file.read_text())
        return {}

    def save_state(self, state: dict) -> None:
        self.state_file.write_text(json.dumps(state, indent=1))

    def journal(self, entry: dict) -> None:
        with open(self.dir / "journal.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, default=str) + "\n")

    def recent_decisions(self, n: int = 5) -> list[dict]:
        path = self.dir / "journal.jsonl"
        if not path.exists():
            return []
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()[-n:]]
        return [{"time": r["time"], "kind": r["kind"], "market_view": r["decision"]["market_view"],
                 "actions": r["results"]} for r in rows if "decision" in r]

    # -- the cycle -------------------------------------------------------------------------
    def cycle(self, kind: str) -> dict:
        """kind: "daily" (new trades allowed) or "manage" (only closes and stop moves)."""
        b, cfg = self.broker, self.cfg
        now = datetime.now(timezone.utc).isoformat(timespec="seconds")
        account = b.account()
        state = self.load_state()
        if "start_equity" not in state or state.get("login") != account.login:
            state = {"login": account.login, "start_equity": account.equity, "halted": False}
        gate = self.risk.trading_allowed(account, state["start_equity"], b.realized_loss_today(),
                                         state.get("halted", False), (self.dir / "STOP").exists())
        if not account.is_demo:
            # Never ask Claude, never touch anything, on a non-demo account.
            entry = {"time": now, "kind": kind, "skipped": gate.reason}
            self.journal(entry)
            self.log(f"REFUSED: {gate.reason}")
            return entry
        if account.equity <= state["start_equity"] * (1 - cfg.max_drawdown_pct / 100):
            state["halted"] = True          # stays halted until state.json is reset by hand
        self.save_state(state)

        universe = load_universe(b.provider, self.symbols)
        setups, watch, warnings = scan(universe, b.provider)
        atr = {s: float(p.atr[-1]) for s, p in universe.pairs.items()}
        positions = b.positions()
        loss_at_stop = {}
        for p in positions:
            if p.stop is not None:
                loss_at_stop[p.ticket] = position_risk(p, b.loss_per_lot(p.symbol, p.direction, p.entry, p.stop))
            else:
                loss_at_stop[p.ticket] = float("inf")
        open_risk = sum(v for v in loss_at_stop.values() if np.isfinite(v))
        new_trades_allowed = kind == "daily" and gate.ok

        snapshot = {
            "time_utc": now, "cycle": kind, "bar_date": str(universe.last_date.date()),
            "new_trades_allowed": new_trades_allowed,
            "why_not": None if new_trades_allowed else (gate.reason if not gate.ok else "management cycle"),
            "account": {"currency": account.currency, "balance": round(account.balance, 2),
                        "equity": round(account.equity, 2),
                        "open_risk_pct": round(100 * open_risk / account.balance, 2)},
            "limits": {"max_risk_per_trade_pct": cfg.max_risk_per_trade_pct,
                       "max_total_risk_pct": cfg.max_total_risk_pct, "max_positions": cfg.max_positions,
                       "max_per_currency": cfg.max_per_currency,
                       "stop_distance_atr": [cfg.min_stop_atr, cfg.max_stop_atr]},
            "positions": [{"ticket": p.ticket, "symbol": p.symbol,
                           "direction": "long" if p.direction > 0 else "short", "volume": p.volume,
                           "entry": p.entry, "stop": p.stop, "target": p.target,
                           "floating_profit": round(p.profit, 2), "opened": p.opened,
                           "daily_atr": atr.get(p.symbol)} for p in positions],
            "setups": [{k: v for k, v in s.to_dict().items() if k != "nearby_levels"} for s in setups],
            "watchlist": watch,
            "currency_strength": {c: round(float(v), 2) for c, v in
                                  universe.strength.dropna(how="all").iloc[-1].items()}
            if len(universe.strength) else {},
            "data_warnings": warnings,
            "your_recent_decisions": self.recent_decisions(),
        }
        if kind == "manage" and not positions:
            decision = Decision.nothing("nothing open to manage")
        else:
            decision = self.brain.decide(snapshot)
        results = self._apply(decision, account, positions, open_risk, atr, new_trades_allowed)
        entry = {"time": now, "kind": kind, "dry_run": self.dry_run, "bar_date": snapshot["bar_date"],
                 "equity": account.equity, "setups": [f"{s.symbol} {s.side} {s.kind}" for s in setups],
                 "decision": decision.model_dump(), "results": results}
        self.journal(entry)
        self.log(f"[{kind}] {decision.market_view}")
        for r in results:
            self.log("   " + r)
        return entry

    def _apply(self, d: Decision, account, positions, open_risk, atr, new_trades_allowed) -> list[str]:
        b, out = self.broker, []
        by_ticket = {p.ticket: p for p in positions}
        tag = "DRY RUN, not sent: " if self.dry_run else ""

        for c in d.closes:
            p = by_ticket.get(c.ticket)
            if p is None:
                out.append(f"close {c.ticket}: dropped - not one of the bot's positions")
                continue
            fill = b.close(c.ticket) if not self.dry_run else None
            ok = self.dry_run or fill.ok
            out.append(f"{tag}close {p.symbol} #{c.ticket}: {'done' if ok else fill.message} ({c.reason})")
            if ok:
                positions = [x for x in positions if x.ticket != c.ticket]
                by_ticket.pop(c.ticket)

        for m in d.stop_moves:
            p = by_ticket.get(m.ticket)
            if p is None:
                out.append(f"move stop {m.ticket}: dropped - not one of the bot's positions")
                continue
            v = self.risk.check_move_stop(m, p, b.quote(p.symbol))
            if not v.ok:
                out.append(f"move stop {p.symbol} #{m.ticket}: dropped - {v.reason}")
                continue
            fill = b.modify(m.ticket, m.new_stop, p.target) if not self.dry_run else None
            ok = self.dry_run or fill.ok
            out.append(f"{tag}move stop {p.symbol} #{m.ticket} to {m.new_stop}: "
                       f"{'done' if ok else fill.message} ({m.reason})")

        for t in d.opens:
            sym = t.symbol.upper()
            if not new_trades_allowed:
                out.append(f"open {sym}: dropped - new trades are not allowed in this cycle")
                continue
            if sym not in atr:
                out.append(f"open {sym}: dropped - no data for this symbol")
                continue
            try:
                q = b.quote(sym)
            except Exception as exc:
                out.append(f"open {sym}: dropped - {exc}")
                continue
            dirn = 1 if t.direction == "long" else -1
            entry = q.ask if dirn > 0 else q.bid
            v = self.risk.check_open(t, account, positions, open_risk, q, atr[sym],
                                     b.loss_per_lot(sym, dirn, entry, t.stop), self.symbols)
            if not v.ok:
                out.append(f"open {sym} {t.direction}: dropped - {v.reason}")
                continue
            if self.dry_run:
                out.append(f"{tag}open {sym} {t.direction} {v.volume} lots, stop {t.stop}, "
                           f"target {t.target}, risk {v.risk_money} {account.currency} ({t.reason})")
                continue
            fill = b.open(sym, dirn, v.volume, t.stop, t.target, "fxbot")
            if fill.ok:
                out.append(f"open {sym} {t.direction} {v.volume} lots at {fill.price}, stop {t.stop}, "
                           f"target {t.target}, risk {v.risk_money} {account.currency} ({t.reason})")
                open_risk += v.risk_money
                positions = b.positions()
            else:
                out.append(f"open {sym} {t.direction}: broker said {fill.message}")
        return out
