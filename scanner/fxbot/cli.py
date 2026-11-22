"""python -m fxbot check | once | run   (see scanner/fxbot/README.md)"""
from __future__ import annotations

import argparse
import sys
import time
from datetime import datetime, timezone

from .brain import Brain
from .config import Config
from .engine import Engine


def _connect(cfg: Config):
    from .broker import MT5Broker
    return MT5Broker(cfg.magic, cfg.symbol_suffix)


def _stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def check(cfg: Config) -> int:
    b = _connect(cfg)
    a = b.account()
    print(f"account {a.login} on {a.server}: {a.balance:.2f} {a.currency}, "
          f"{'DEMO' if a.is_demo else 'NOT A DEMO ACCOUNT - the bot will refuse to trade'}")
    eng = Engine(cfg, b, None, dry_run=True)
    missing = []
    for s in eng.symbols:
        try:
            q = b.quote(s)
            print(f"  {s:7s} -> {b.name(s):12s} bid {q.bid} ask {q.ask} min lot {q.min_lot}")
        except Exception as exc:
            missing.append(s)
            print(f"  {s:7s} -> not available ({exc})")
    print(f"{len(eng.symbols) - len(missing)} of {len(eng.symbols)} symbols available; "
          f"{len(b.positions())} open bot positions")
    return 0 if a.is_demo else 1


def run_loop(eng: Engine, cfg: Config) -> int:
    print(f"{_stamp()} autopilot started. Ctrl+C stops it; open positions keep their stops.")
    last_manage = 0.0
    while True:
        try:
            state = eng.load_state()
            age = eng.broker.forming_bar_age_minutes()
            today = datetime.now(timezone.utc)
            bar_id = eng.broker.provider.daily("EURUSD").index[-1].strftime("%Y-%m-%d")
            if state.get("last_daily_bar") != bar_id and age >= cfg.entry_delay_minutes:
                # after a late start (bar already old) only manage: yesterday's setups are stale
                kind = "daily" if age <= 6 * 60 else "manage"
                print(f"{_stamp()} {kind} cycle for bar {bar_id}")
                eng.cycle(kind)
                state = eng.load_state()
                state["last_daily_bar"] = bar_id
                eng.save_state(state)
                last_manage = time.time()
            elif (time.time() - last_manage >= cfg.manage_every_hours * 3600
                  and today.weekday() < 5 and eng.broker.positions()):
                print(f"{_stamp()} manage cycle")
                eng.cycle("manage")
                last_manage = time.time()
        except KeyboardInterrupt:
            print("stopped")
            return 0
        except Exception as exc:   # keep running through data or connection hiccups
            print(f"{_stamp()} cycle failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        try:
            time.sleep(300)
        except KeyboardInterrupt:
            print("stopped")
            return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="fxbot", description=__doc__)
    ap.add_argument("command", choices=["check", "once", "run"])
    ap.add_argument("--dry-run", action="store_true", help="decide and log, but send no orders")
    ap.add_argument("--manage", action="store_true", help="with 'once': a management cycle (no new trades)")
    ap.add_argument("--config", help="path to fxbot.toml")
    args = ap.parse_args(argv)
    cfg = Config.load(args.config)
    if args.command == "check":
        return check(cfg)
    eng = Engine(cfg, _connect(cfg), Brain(cfg), dry_run=args.dry_run)
    if args.command == "once":
        eng.cycle("manage" if args.manage else "daily")
        return 0
    return run_loop(eng, cfg)
