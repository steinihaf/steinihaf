"""Data shapes: what Claude must return, and what brokers report."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, Field


class OpenTrade(BaseModel):
    symbol: str = Field(description="Instrument, e.g. EURUSD")
    direction: Literal["long", "short"]
    stop: float = Field(description="Stop-loss price")
    target: float | None = Field(description="Take-profit price, or null for none")
    risk_pct: float = Field(description="Percent of balance to risk on this trade")
    reason: str


class CloseTrade(BaseModel):
    ticket: int
    reason: str


class MoveStop(BaseModel):
    ticket: int
    new_stop: float = Field(description="New stop-loss price; may only reduce risk")
    reason: str


class Decision(BaseModel):
    market_view: str = Field(description="Two or three sentences on what you see")
    opens: list[OpenTrade]
    closes: list[CloseTrade]
    stop_moves: list[MoveStop]

    @classmethod
    def nothing(cls, why: str) -> "Decision":
        return cls(market_view=why, opens=[], closes=[], stop_moves=[])


@dataclass
class Account:
    login: int
    server: str
    currency: str
    balance: float
    equity: float
    is_demo: bool


@dataclass
class Quote:
    bid: float
    ask: float
    min_lot: float
    lot_step: float
    max_lot: float
    digits: int


@dataclass
class Position:
    ticket: int
    symbol: str          # scanner name (EURUSD), not the broker's suffixed name
    direction: int       # +1 long, -1 short
    volume: float
    entry: float
    stop: float | None
    target: float | None
    profit: float        # floating, account currency
    opened: str


@dataclass
class Fill:
    ok: bool
    message: str
    ticket: int | None = None
    price: float | None = None
