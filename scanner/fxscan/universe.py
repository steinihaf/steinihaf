"""The instruments the scanner covers and their trading conventions."""
from __future__ import annotations

from dataclasses import dataclass

CURRENCIES = ["EUR", "GBP", "AUD", "NZD", "USD", "CAD", "CHF", "JPY"]

# Market-convention names of the 28 pairs formed by the 8 major currencies.
FX_PAIRS = [
    "EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDCHF", "USDJPY",
    "EURGBP", "EURAUD", "EURNZD", "EURCAD", "EURCHF", "EURJPY",
    "GBPAUD", "GBPNZD", "GBPCAD", "GBPCHF", "GBPJPY",
    "AUDNZD", "AUDCAD", "AUDCHF", "AUDJPY",
    "NZDCAD", "NZDCHF", "NZDJPY",
    "CADCHF", "CADJPY", "CHFJPY",
]
METALS = ["XAUUSD"]
ALL_SYMBOLS = FX_PAIRS + METALS

# Round-trip cost assumed by the backtest, in pips. These are assumptions for a typical
# retail ECN-style account, not quotes from any broker: replace them with your own.
_SPREAD_PIPS = {
    "EURUSD": 0.8, "USDJPY": 0.9, "GBPUSD": 1.2, "AUDUSD": 1.0, "USDCAD": 1.5,
    "USDCHF": 1.3, "NZDUSD": 1.5, "EURGBP": 1.2, "EURJPY": 1.5, "EURCHF": 1.8,
    "XAUUSD": 3.0,
}
_DEFAULT_CROSS_SPREAD_PIPS = 2.5


@dataclass(frozen=True)
class Instrument:
    symbol: str
    base: str
    quote: str
    pip: float          # price value of one pip
    digits: int         # decimals to print prices with
    spread_pips: float  # assumed round-trip cost
    is_fx: bool

    @property
    def spread(self) -> float:
        return self.spread_pips * self.pip


def instrument(symbol: str) -> Instrument:
    symbol = symbol.upper()
    if symbol == "XAUUSD":
        return Instrument(symbol, "XAU", "USD", 0.1, 2, _SPREAD_PIPS[symbol], False)
    if len(symbol) != 6:
        raise ValueError(f"unknown symbol {symbol!r}")
    base, quote = symbol[:3], symbol[3:]
    jpy = quote == "JPY"
    return Instrument(symbol, base, quote, 0.01 if jpy else 0.0001, 3 if jpy else 5,
                      _SPREAD_PIPS.get(symbol, _DEFAULT_CROSS_SPREAD_PIPS), True)
