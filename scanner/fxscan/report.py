"""Render scan and backtest results as Markdown and JSON."""
from __future__ import annotations

import json
from datetime import datetime, timezone

from .universe import instrument

DISCLAIMER = ("Rules-based scan of daily price data. It lists setups that match the "
              "rules; it does not predict outcomes and is not financial advice.")


def _px(symbol: str, v) -> str:
    return "-" if v is None else f"{v:.{instrument(symbol).digits}f}"


def scan_payload(universe, setups, watch, warnings, backtest_summary=None) -> dict:
    last = universe.strength.dropna(how="all").iloc[-1] if len(universe.strength) else None
    prev = universe.strength.dropna(how="all").iloc[-6] if len(universe.strength) > 6 else None
    strength = []
    if last is not None:
        for ccy, v in last.sort_values(ascending=False).items():
            strength.append({"currency": ccy, "strength": round(float(v), 2),
                             "change_5d": None if prev is None else round(float(v - prev[ccy]), 2)})
    return {
        "generated_utc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M"),
        "bar_date": str(universe.last_date.date()),
        "instruments_scanned": len(universe.pairs),
        "setups": [s.to_dict() for s in setups],
        "watchlist": watch,
        "strength": strength,
        "warnings": warnings,
        "backtest": backtest_summary,
        "disclaimer": DISCLAIMER,
    }


def scan_markdown(payload: dict) -> str:
    L = [f"# Forex swing scan - daily bar of {payload['bar_date']}", "",
         f"Generated {payload['generated_utc']} UTC. {payload['instruments_scanned']} instruments scanned, "
         f"{len(payload['setups'])} setups, {len(payload['watchlist'])} on watch.", "",
         f"_{DISCLAIMER}_", ""]
    L += ["## Setups", ""]
    if not payload["setups"]:
        L += ["No instrument completed a setup on this bar.", ""]
    else:
        L += ["| # | Pair | Side | Setup | Score | Entry | Stop | Target (2R) | Risk (pips) | H4 |",
              "|---|---|---|---|---|---|---|---|---|---|"]
        for i, s in enumerate(payload["setups"], 1):
            sym = s["symbol"]
            L.append(f"| {i} | {sym} | {'long' if s['direction'] > 0 else 'short'} | {s['kind']} | "
                     f"{s['score']} | {_px(sym, s['entry'])} | {_px(sym, s['stop'])} | "
                     f"{_px(sym, s['target'])} | {s['risk_pips']} | {s['h4_state'] or '-'} |")
        L.append("")
        for s in payload["setups"]:
            sym = s["symbol"]
            L += [f"### {sym} {'long' if s['direction'] > 0 else 'short'} - {s['kind']} (score {s['score']})", ""]
            L += [f"- For: {'; '.join(s['reasons'])}."]
            if s["cautions"]:
                L += [f"- Against: {'; '.join(s['cautions'])}."]
            if s["level"] is not None:
                L += [f"- Level: {_px(sym, s['level'])} (grade {s['level_grade']}, {s['level_sources']})."]
            if s["nearby_levels"]:
                lv = ";".join(_px(sym, v) for v in s["nearby_levels"])
                L += [f"- Levels near price, ready for LineTouchEA `InpManualLevels`: `{lv}`"]
            L.append("")
    L += ["## Watchlist (trend pullbacks waiting for a trigger)", ""]
    if payload["watchlist"]:
        L += ["| Pair | Trend | Close | Note |", "|---|---|---|---|"]
        for w in payload["watchlist"]:
            L.append(f"| {w['symbol']} | {w['trend']} | {_px(w['symbol'], w['close'])} | {w['note']} |")
    else:
        L.append("Nothing waiting.")
    L += ["", "## Currency strength (20-day move in ATR units)", ""]
    if payload["strength"]:
        L += ["| Currency | Strength | 5-day change |", "|---|---|---|"]
        for r in payload["strength"]:
            ch = "-" if r["change_5d"] is None else f"{r['change_5d']:+.2f}"
            L.append(f"| {r['currency']} | {r['strength']:+.2f} | {ch} |")
    if payload["warnings"]:
        L += ["", "## Data warnings", ""] + [f"- {w}" for w in payload["warnings"]]
    return "\n".join(L) + "\n"


def _row(name, s) -> str:
    if not s.get("trades"):
        return f"| {name} | 0 | - | - | - | - | - |"
    pf = "-" if s["profit_factor"] is None else f"{s['profit_factor']:.2f}"
    return (f"| {name} | {s['trades']} | {s['win_rate']:.0%} | {s['avg_r']:+.3f} ± {s['avg_r_se']:.3f} | "
            f"{s['total_r']:+.1f} | {pf} | {s['max_drawdown_r']:.1f} |")


HEAD = ["| Group | Trades | Win rate | Avg R ± s.e. | Total R | Profit factor | Max drawdown (R) |",
        "|---|---|---|---|---|---|---|"]


def backtest_markdown(bt: dict) -> str:
    L = ["# Backtest of the scanner's rules", ""]
    if not bt["overall"].get("trades"):
        return "\n".join(L + ["No trades."]) + "\n"
    L += [f"Trades from {bt['period'][0]} to {bt['period'][1]}. Results in R (multiples of the "
          "initial risk), after the assumed spread; swaps and commissions are not included.", "",
          "An average R within about two standard errors of zero is not evidence of an edge.", ""]
    L += ["## Overall", ""] + HEAD + [_row("all", bt["overall"]), ""]
    for title, key in (("By setup", "by_kind"), ("By score bucket", "by_bucket"),
                       ("By setup and score bucket", "by_kind_bucket"), ("By side", "by_side"),
                       ("By year", "by_year"), ("By instrument", "by_symbol")):
        L += [f"## {title}", ""] + HEAD + [_row(k, v) for k, v in bt[key].items()] + [""]
    return "\n".join(L)


def backtest_summary(bt: dict) -> dict:
    return {k: v for k, v in bt.items() if k != "trades"}


def dump_json(obj, path) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=1, default=str)
        f.write("\n")
