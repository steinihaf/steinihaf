"""Command line: python -m fxscan scan | backtest"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import backtest as bt
from . import report
from .data import CsvProvider, OandaProvider
from .scan import load_universe, scan
from .universe import ALL_SYMBOLS

ROOT = Path(__file__).resolve().parent.parent


def _provider(args):
    if args.csv_dir:
        return CsvProvider(args.csv_dir)
    return OandaProvider(account=args.oanda_account, cache_dir=ROOT / ".cache",
                         cache_minutes=args.cache_minutes)


def _log(args):
    return (lambda m: print(m, file=sys.stderr)) if args.verbose else None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="fxscan", description=__doc__)
    ap.add_argument("command", choices=["scan", "backtest"])
    ap.add_argument("--symbols", help="comma-separated list (default: 28 FX pairs + XAUUSD)")
    ap.add_argument("--csv-dir", help="read <SYMBOL>_D1.csv / _H4.csv from this folder instead of OANDA")
    ap.add_argument("--oanda-account", choices=["practice", "live"], default="practice",
                    help="which OANDA API host the token belongs to (data only; no orders are sent)")
    ap.add_argument("--out", default=str(ROOT / "out"), help="output folder (default: scanner/out)")
    ap.add_argument("--years", type=int, default=10, help="years of daily history to load")
    ap.add_argument("--cache-minutes", type=float, default=30)
    ap.add_argument("--no-h4", action="store_true", help="skip the 4-hour timing check")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args(argv)

    symbols = [s.strip().upper() for s in args.symbols.split(",")] if args.symbols else ALL_SYMBOLS
    provider = _provider(args)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    universe = load_universe(provider, symbols, years=args.years, log=_log(args))

    if args.command == "scan":
        setups, watch, warnings = scan(universe, None if args.no_h4 else provider)
        summary = None
        bt_file = out / "backtest.json"
        if bt_file.exists():
            summary = json.loads(bt_file.read_text())
        payload = report.scan_payload(universe, setups, watch, warnings, summary)
        report.dump_json(payload, out / "scan.json")
        md = report.scan_markdown(payload)
        (out / "scan.md").write_text(md, encoding="utf-8")
        print(md)
    else:
        res = bt.run(universe.pairs, log=_log(args))
        report.dump_json(report.backtest_summary(res), out / "backtest.json")
        report.dump_json([t.to_dict() for t in res["trades"]], out / "backtest_trades.json")
        md = report.backtest_markdown(res)
        (out / "backtest.md").write_text(md, encoding="utf-8")
        print(md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
