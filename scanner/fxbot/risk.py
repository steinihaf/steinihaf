"""Hard limits. Every action Claude proposes passes through here; nothing here asks Claude.

Position size is always computed by this module from the risk percentage and the stop
distance - a lot size is never taken from the model.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from fxscan.universe import ALL_SYMBOLS, instrument

from .config import Config
from .models import Account, MoveStop, OpenTrade, Position, Quote


@dataclass
class Verdict:
    ok: bool
    reason: str
    volume: float = 0.0
    risk_money: float = 0.0


def currencies(symbol: str) -> tuple[str, str]:
    ins = instrument(symbol)
    return ins.base, ins.quote


def position_risk(p: Position, loss_per_lot_at_stop: float | None) -> float:
    """Money lost if the position's stop is hit (0 once the stop locks in a profit)."""
    if p.stop is None:
        return float("inf")
    if (p.stop - p.entry) * p.direction >= 0:
        return 0.0
    return (loss_per_lot_at_stop or 0.0) * p.volume


class RiskManager:
    def __init__(self, cfg: Config):
        self.cfg = cfg

    # -- account-level gates -------------------------------------------------------------
    def trading_allowed(self, account: Account, start_equity: float, loss_today: float,
                        halted: bool, stop_file: bool) -> Verdict:
        if not account.is_demo:
            return Verdict(False, "not a demo account - this bot only trades demo accounts")
        if stop_file:
            return Verdict(False, "STOP file present")
        if halted:
            return Verdict(False, "halted earlier by the drawdown limit")
        if account.equity <= start_equity * (1 - self.cfg.max_drawdown_pct / 100):
            return Verdict(False, f"equity is {self.cfg.max_drawdown_pct:g}% below the starting equity")
        if loss_today >= account.balance * self.cfg.daily_loss_stop_pct / 100:
            return Verdict(False, f"today's loss reached {self.cfg.daily_loss_stop_pct:g}% of balance")
        return Verdict(True, "ok")

    # -- a new trade ---------------------------------------------------------------------
    def check_open(self, t: OpenTrade, account: Account, positions: list[Position],
                   open_risk: float, quote: Quote, atr: float, loss_per_lot: float,
                   allowed_symbols=ALL_SYMBOLS) -> Verdict:
        cfg = self.cfg
        sym = t.symbol.upper()
        if sym not in allowed_symbols:
            return Verdict(False, f"{sym} is not in the bot's universe")
        if any(p.symbol == sym for p in positions):
            return Verdict(False, f"already holding {sym}")
        if len(positions) >= cfg.max_positions:
            return Verdict(False, f"already at {cfg.max_positions} open positions")
        for ccy in currencies(sym):
            n = sum(ccy in currencies(p.symbol) for p in positions)
            if n >= cfg.max_per_currency:
                return Verdict(False, f"already {n} open positions involving {ccy}")
        d = 1 if t.direction == "long" else -1
        entry = quote.ask if d > 0 else quote.bid
        ins = instrument(sym)
        spread = quote.ask - quote.bid
        if spread > cfg.max_spread_mult * ins.spread:
            return Verdict(False, f"spread {spread / ins.pip:.1f} pips is too wide right now")
        dist = (entry - t.stop) * d
        if not math.isfinite(t.stop) or dist <= 0:
            return Verdict(False, "stop is on the wrong side of the price")
        if not (cfg.min_stop_atr * atr <= dist <= cfg.max_stop_atr * atr):
            return Verdict(False, f"stop distance {dist / atr:.2f} ATR is outside "
                                  f"{cfg.min_stop_atr:g}-{cfg.max_stop_atr:g} ATR")
        if t.target is not None and (not math.isfinite(t.target) or (t.target - entry) * d < dist):
            return Verdict(False, "target is closer than 1R or on the wrong side")
        if not math.isfinite(t.risk_pct) or t.risk_pct <= 0:
            return Verdict(False, "risk must be positive")
        risk_pct = min(t.risk_pct, cfg.max_risk_per_trade_pct)
        risk_money = account.balance * risk_pct / 100
        budget = account.balance * cfg.max_total_risk_pct / 100 - open_risk
        if budget <= 0:
            return Verdict(False, f"open risk already at {cfg.max_total_risk_pct:g}% of balance")
        risk_money = min(risk_money, budget)
        if loss_per_lot <= 0:
            return Verdict(False, "could not price the stop distance for this symbol")
        steps = math.floor(risk_money / loss_per_lot / quote.lot_step + 1e-9)
        volume = round(steps * quote.lot_step, 8)
        if volume < quote.min_lot:
            return Verdict(False, f"the smallest lot would risk more than the allowed "
                                  f"{risk_money:.2f} {account.currency}")
        volume = min(volume, quote.max_lot)
        return Verdict(True, "ok", volume=volume, risk_money=round(volume * loss_per_lot, 2))

    # -- an existing trade ---------------------------------------------------------------
    @staticmethod
    def check_move_stop(m: MoveStop, p: Position, quote: Quote) -> Verdict:
        price = quote.bid if p.direction > 0 else quote.ask
        if not math.isfinite(m.new_stop) or (price - m.new_stop) * p.direction <= 0:
            return Verdict(False, "new stop is on the wrong side of the price")
        if p.stop is not None and (m.new_stop - p.stop) * p.direction <= 0:
            return Verdict(False, "a stop may only be moved to reduce risk")
        return Verdict(True, "ok")
