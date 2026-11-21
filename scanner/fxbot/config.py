"""Settings. Defaults are deliberately small; override them in fxbot.toml next to the scanner."""
from __future__ import annotations

import tomllib
from dataclasses import dataclass, fields
from pathlib import Path


@dataclass
class Config:
    # --- Claude ---
    model: str = "claude-opus-5-5"
    effort: str = "medium"
    # --- hard risk limits, enforced in code whatever Claude answers ---
    max_risk_per_trade_pct: float = 0.5     # of balance, per trade
    max_total_risk_pct: float = 2.0         # sum of open risk across positions
    max_positions: int = 4
    max_per_currency: int = 2               # open positions that share a currency
    daily_loss_stop_pct: float = 2.0        # no new trades once today's loss reaches this
    max_drawdown_pct: float = 10.0          # from the starting equity: halts the bot for good
    min_stop_atr: float = 0.5               # stop distance bounds, in daily ATR
    max_stop_atr: float = 4.0
    max_spread_mult: float = 3.0            # skip an entry when spread > this x the usual one
    # --- behaviour ---
    magic: int = 20261121                   # tags the bot's own orders; it never touches others
    entry_delay_minutes: int = 75           # wait after the daily close (rollover spreads)
    manage_every_hours: float = 4.0
    symbol_suffix: str = ""                 # e.g. ".m" if your broker names pairs EURUSD.m
    symbols: str = ""                       # comma list to restrict the universe; empty = all 29
    state_dir: str = "bot_state"

    @classmethod
    def load(cls, path: str | Path | None = None) -> "Config":
        cfg = cls()
        path = Path(path) if path else Path(__file__).resolve().parent.parent / "fxbot.toml"
        if path.exists():
            data = tomllib.loads(path.read_text(encoding="utf-8"))
            known = {f.name: f.type for f in fields(cls)}
            for key, value in data.items():
                if key not in known:
                    raise ValueError(f"{path.name}: unknown setting {key!r}")
                setattr(cfg, key, type(getattr(cfg, key))(value))
        cfg.validate()
        return cfg

    def validate(self) -> None:
        if not 0 < self.max_risk_per_trade_pct <= 2:
            raise ValueError("max_risk_per_trade_pct must be between 0 and 2")
        if not 0 < self.max_total_risk_pct <= 10:
            raise ValueError("max_total_risk_pct must be between 0 and 10")
        if self.max_positions < 1 or self.max_per_currency < 1:
            raise ValueError("max_positions and max_per_currency must be at least 1")
        if not 0 < self.min_stop_atr < self.max_stop_atr:
            raise ValueError("stop bounds must satisfy 0 < min_stop_atr < max_stop_atr")
