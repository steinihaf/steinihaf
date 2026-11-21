"""Brokers. PaperBroker is an in-memory simulation for tests and dry runs; MT5Broker talks
to a running MetaTrader 5 terminal through the official MetaTrader5 Python package
(Windows only)."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pandas as pd

from fxscan.data import COLUMNS, DataError, clean
from fxscan.universe import instrument

from .models import Account, Fill, Position, Quote


class PaperBroker:
    """Fills at the quoted price, holds positions in memory. Prices come from `quotes`."""

    def __init__(self, provider, balance: float = 10_000.0, demo: bool = True, currency: str = "USD"):
        self.provider = provider
        self._acct = Account(1, "paper", currency, balance, balance, demo)
        self.quotes: dict[str, Quote] = {}
        self._positions: dict[int, Position] = {}
        self._next = 1000
        self.loss_today = 0.0

    def account(self) -> Account:
        return self._acct

    def quote(self, symbol: str) -> Quote:
        if symbol not in self.quotes:
            df = self.provider.daily(symbol)
            ins = instrument(symbol)
            c = float(df["close"].iloc[-1])
            self.quotes[symbol] = Quote(c - ins.spread / 2, c + ins.spread / 2, 0.01, 0.01, 100.0, ins.digits)
        return self.quotes[symbol]

    def loss_per_lot(self, symbol: str, direction: int, entry: float, stop: float) -> float:
        """Rough USD value of the stop distance for one lot (a simulation, not broker maths)."""
        ins = instrument(symbol)
        loss = abs(entry - stop) * (100_000.0 if ins.is_fx else 100.0)   # in the quote currency
        if ins.quote == "USD":
            return loss
        if ins.base == "USD":
            return loss / entry
        return loss / 150.0 if ins.quote == "JPY" else loss            # crosses: approximate

    def positions(self) -> list[Position]:
        return list(self._positions.values())

    def realized_loss_today(self) -> float:
        return self.loss_today

    def open(self, symbol, direction, volume, stop, target, comment="") -> Fill:
        q = self.quote(symbol)
        price = q.ask if direction > 0 else q.bid
        self._next += 1
        self._positions[self._next] = Position(self._next, symbol, direction, volume, price, stop,
                                               target, 0.0, datetime.now(timezone.utc).isoformat())
        return Fill(True, "filled (paper)", self._next, price)

    def close(self, ticket: int) -> Fill:
        if ticket not in self._positions:
            return Fill(False, f"no position {ticket}")
        self._positions.pop(ticket)
        return Fill(True, "closed (paper)", ticket)

    def modify(self, ticket: int, stop, target) -> Fill:
        if ticket not in self._positions:
            return Fill(False, f"no position {ticket}")
        self._positions[ticket].stop = stop
        self._positions[ticket].target = target
        return Fill(True, "modified (paper)", ticket)

    def forming_bar_age_minutes(self) -> float:
        return 24 * 60.0


class MT5Broker:
    """Live connection to the MetaTrader 5 terminal that is open and logged in on this PC.

    Only positions carrying this bot's magic number are ever read, changed or closed.
    """

    def __init__(self, magic: int, suffix: str = ""):
        import MetaTrader5 as mt5   # imported here: the package exists on Windows only
        self.mt5 = mt5
        self.magic = magic
        self.suffix = suffix
        self._names: dict[str, str] = {}
        if not mt5.initialize():
            raise ConnectionError(f"MetaTrader 5 is not reachable: {mt5.last_error()}")
        self.provider = _MT5Provider(self)

    # -- names -----------------------------------------------------------------------------
    def name(self, symbol: str) -> str:
        """The broker's own name for a scanner symbol (handles suffixes such as EURUSD.m)."""
        if symbol in self._names:
            return self._names[symbol]
        mt5 = self.mt5
        candidates = [symbol + self.suffix, symbol]
        if symbol == "XAUUSD":
            candidates += ["GOLD" + self.suffix, "GOLD"]
        found = next((c for c in candidates if mt5.symbol_info(c) is not None), None)
        if found is None:
            matches = [s.name for s in (mt5.symbols_get(f"{symbol}*") or [])]
            found = min(matches, key=len) if matches else None
        if found is None:
            raise DataError(f"{symbol}: no such symbol at this broker")
        mt5.symbol_select(found, True)
        self._names[symbol] = found
        return found

    def _scanner_symbol(self, broker_name: str) -> str:
        for k, v in self._names.items():
            if v == broker_name:
                return k
        return broker_name[:6].upper() if not broker_name.upper().startswith("GOLD") else "XAUUSD"

    # -- account and prices ----------------------------------------------------------------
    def account(self) -> Account:
        a = self.mt5.account_info()
        if a is None:
            raise ConnectionError(f"no account info: {self.mt5.last_error()}")
        return Account(a.login, a.server, a.currency, a.balance, a.equity,
                       a.trade_mode == self.mt5.ACCOUNT_TRADE_MODE_DEMO)

    def quote(self, symbol: str) -> Quote:
        n = self.name(symbol)
        info, tick = self.mt5.symbol_info(n), self.mt5.symbol_info_tick(n)
        if info is None or tick is None or tick.bid <= 0 or tick.ask <= 0:
            raise DataError(f"{symbol}: no live quote")
        return Quote(tick.bid, tick.ask, info.volume_min, info.volume_step, info.volume_max, info.digits)

    def loss_per_lot(self, symbol: str, direction: int, entry: float, stop: float) -> float:
        mt5 = self.mt5
        kind = mt5.ORDER_TYPE_BUY if direction > 0 else mt5.ORDER_TYPE_SELL
        profit = mt5.order_calc_profit(kind, self.name(symbol), 1.0, entry, stop)
        return -profit if profit is not None and profit < 0 else 0.0

    def rates(self, symbol: str, timeframe, count: int) -> pd.DataFrame:
        r = self.mt5.copy_rates_from_pos(self.name(symbol), timeframe, 0, count)
        if r is None or len(r) == 0:
            raise DataError(f"{symbol}: no bars ({self.mt5.last_error()})")
        df = pd.DataFrame(r)
        df.index = pd.to_datetime(df["time"], unit="s")     # broker server time
        return df[COLUMNS]

    def forming_bar_age_minutes(self) -> float:
        """Minutes since the current daily bar opened, measured on the broker's own clock."""
        n = self.name("EURUSD")
        r = self.mt5.copy_rates_from_pos(n, self.mt5.TIMEFRAME_D1, 0, 1)
        tick = self.mt5.symbol_info_tick(n)
        if r is None or len(r) == 0 or tick is None:
            raise DataError("cannot read the daily bar clock")
        return (tick.time - int(r[0]["time"])) / 60.0

    # -- positions -------------------------------------------------------------------------
    def positions(self) -> list[Position]:
        mt5 = self.mt5
        out = []
        for p in mt5.positions_get() or []:
            if p.magic != self.magic:
                continue
            out.append(Position(p.ticket, self._scanner_symbol(p.symbol),
                                1 if p.type == mt5.POSITION_TYPE_BUY else -1, p.volume, p.price_open,
                                p.sl or None, p.tp or None, p.profit,
                                datetime.fromtimestamp(p.time, timezone.utc).isoformat()))
        return out

    def realized_loss_today(self) -> float:
        mt5 = self.mt5
        now = datetime.now(timezone.utc)
        deals = mt5.history_deals_get(now.replace(hour=0, minute=0, second=0, microsecond=0),
                                      now + timedelta(days=1)) or []
        pnl = sum(d.profit + d.swap + d.commission for d in deals
                  if d.magic == self.magic and d.entry == mt5.DEAL_ENTRY_OUT)
        return max(0.0, -pnl)

    # -- orders ----------------------------------------------------------------------------
    def _filling(self, info):
        mt5 = self.mt5
        if info.filling_mode & 2:
            return mt5.ORDER_FILLING_IOC
        if info.filling_mode & 1:
            return mt5.ORDER_FILLING_FOK
        return mt5.ORDER_FILLING_RETURN

    def _send(self, request: dict) -> Fill:
        mt5 = self.mt5
        res = mt5.order_send(request)
        if res is None:
            return Fill(False, f"order_send failed: {mt5.last_error()}")
        if res.retcode != mt5.TRADE_RETCODE_DONE:
            return Fill(False, f"rejected: retcode {res.retcode} {res.comment}")
        return Fill(True, "done", res.order or request.get("position"), res.price or None)

    def open(self, symbol, direction, volume, stop, target, comment="") -> Fill:
        mt5 = self.mt5
        n = self.name(symbol)
        info, tick = mt5.symbol_info(n), mt5.symbol_info_tick(n)
        req = {
            "action": mt5.TRADE_ACTION_DEAL, "symbol": n, "volume": float(volume),
            "type": mt5.ORDER_TYPE_BUY if direction > 0 else mt5.ORDER_TYPE_SELL,
            "price": tick.ask if direction > 0 else tick.bid,
            "sl": round(float(stop), info.digits), "deviation": 20, "magic": self.magic,
            "comment": comment[:25], "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": self._filling(info),
        }
        if target is not None:
            req["tp"] = round(float(target), info.digits)
        return self._send(req)

    def _own(self, ticket: int):
        for p in self.mt5.positions_get(ticket=ticket) or []:
            if p.magic == self.magic:
                return p
        return None

    def close(self, ticket: int) -> Fill:
        mt5 = self.mt5
        p = self._own(ticket)
        if p is None:
            return Fill(False, f"position {ticket} is not one of the bot's")
        info, tick = mt5.symbol_info(p.symbol), mt5.symbol_info_tick(p.symbol)
        buy = p.type == mt5.POSITION_TYPE_BUY
        return self._send({
            "action": mt5.TRADE_ACTION_DEAL, "symbol": p.symbol, "volume": p.volume,
            "type": mt5.ORDER_TYPE_SELL if buy else mt5.ORDER_TYPE_BUY, "position": p.ticket,
            "price": tick.bid if buy else tick.ask, "deviation": 20, "magic": self.magic,
            "comment": "fxbot close", "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": self._filling(info),
        })

    def modify(self, ticket: int, stop, target) -> Fill:
        mt5 = self.mt5
        p = self._own(ticket)
        if p is None:
            return Fill(False, f"position {ticket} is not one of the bot's")
        info = mt5.symbol_info(p.symbol)
        req = {"action": mt5.TRADE_ACTION_SLTP, "symbol": p.symbol, "position": p.ticket,
               "sl": round(float(stop), info.digits) if stop else 0.0,
               "tp": round(float(target), info.digits) if target else 0.0}
        return self._send(req)


class _MT5Provider:
    """Feeds the scanner with the broker's own bars."""

    def __init__(self, broker: MT5Broker):
        self.b = broker

    def daily(self, symbol: str, years: int = 10) -> pd.DataFrame:
        df = self.b.rates(symbol, self.b.mt5.TIMEFRAME_D1, min(years * 262, 3000))
        df = clean(df.iloc[:-1])                 # the last bar is still forming
        df.index = df.index.normalize()
        return df[df.index.weekday < 5]

    def h4(self, symbol: str, days: int = 120) -> pd.DataFrame:
        df = self.b.rates(symbol, self.b.mt5.TIMEFRAME_H4, days * 6)
        return clean(df.iloc[:-1])
