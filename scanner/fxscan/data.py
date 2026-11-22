"""Price history providers.

A provider returns a DataFrame indexed by a tz-naive UTC DatetimeIndex with the columns
open, high, low, close, oldest bar first. Two providers ship with the scanner:

* TwelveDataProvider - Twelve Data time_series API (needs an API key; free plan works).
* OandaProvider - OANDA v20 REST candles (needs a free practice-account token).
* CsvProvider   - one CSV per symbol and timeframe, e.g. bars exported from MetaTrader.
"""
from __future__ import annotations

import json
import os
import time
from pathlib import Path

import numpy as np
import pandas as pd

COLUMNS = ["open", "high", "low", "close"]


class DataError(RuntimeError):
    pass


def clean(df: pd.DataFrame) -> pd.DataFrame:
    """Drop empty / impossible bars and make each bar internally consistent."""
    df = df[COLUMNS].astype(float).dropna()
    df = df[(df > 0).all(axis=1)]
    df = df[~df.index.duplicated(keep="last")].sort_index()
    df = df.copy()
    df["high"] = df[COLUMNS].max(axis=1)
    df["low"] = df[COLUMNS].min(axis=1)
    return df


def drop_unfinished(df: pd.DataFrame, closes_after: pd.Timedelta,
                    now: pd.Timestamp | None = None) -> pd.DataFrame:
    """Drop the last bar while it is still forming, so signals only use completed bars.

    `closes_after` is how long after its timestamp a bar is final.
    """
    if df.empty:
        return df
    now = now or pd.Timestamp.now(tz="UTC").tz_localize(None)
    return df if now >= df.index[-1] + closes_after else df.iloc[:-1]


# A daily bar stamped at 00:00 UTC of day D is final at the New York close, about 22:00 UTC.
DAILY_CLOSE = pd.Timedelta(hours=22)


class OandaProvider:
    """OANDA v20 REST API (free practice account). Needs a personal access token.

    The token is read from the OANDA_API_TOKEN environment variable. Where a network proxy
    injects the Authorization header for the OANDA host, the variable can be left unset.
    Candles are mid prices with daily bars aligned to the 17:00 New York close.
    """

    HOSTS = {"practice": "https://api-fxpractice.oanda.com", "live": "https://api-fxtrade.oanda.com"}

    def __init__(self, token: str | None = None, account: str = "practice",
                 cache_dir: str | os.PathLike | None = None, cache_minutes: float = 30,
                 session=None):
        self.base = self.HOSTS[account]
        self.token = token or os.environ.get("OANDA_API_TOKEN") or "set-by-proxy"
        self.cache_dir = Path(cache_dir) if cache_dir else None
        self.cache_seconds = cache_minutes * 60
        self._session = session

    @staticmethod
    def oanda_symbol(symbol: str) -> str:
        return f"{symbol[:3]}_{symbol[3:]}"

    def _get(self, symbol: str, granularity: str, count: int) -> dict:
        cache = None
        if self.cache_dir:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            cache = self.cache_dir / f"{symbol}_{granularity}_{count}.json"
            if cache.exists() and time.time() - cache.stat().st_mtime < self.cache_seconds:
                return json.loads(cache.read_text())
        if self._session is None:
            import requests
            self._session = requests.Session()
        url = f"{self.base}/v3/instruments/{self.oanda_symbol(symbol)}/candles"
        params = {"granularity": granularity, "count": count, "price": "M",
                  "dailyAlignment": 17, "alignmentTimezone": "America/New_York"}
        headers = {"Authorization": f"Bearer {self.token}", "Accept-Datetime-Format": "RFC3339"}
        last_error: Exception | None = None
        for attempt in range(4):
            try:
                r = self._session.get(url, params=params, headers=headers, timeout=30)
                if r.status_code == 200:
                    payload = r.json()
                    if cache:
                        cache.write_text(json.dumps(payload))
                    return payload
                last_error = DataError(f"HTTP {r.status_code}: {r.text[:120]}")
                if r.status_code in (400, 401, 403, 404):   # retrying will not help
                    break
            except Exception as exc:   # network errors: retry with backoff
                last_error = exc
            time.sleep(2 ** attempt)
        raise DataError(f"{symbol} {granularity}: download failed ({last_error})")

    def _frame(self, symbol: str, granularity: str, count: int) -> pd.DataFrame:
        candles = [c for c in self._get(symbol, granularity, count).get("candles", [])
                   if c.get("complete")]      # the bar still forming is never used
        if not candles:
            raise DataError(f"{symbol}: no completed {granularity} candles returned")
        idx = pd.to_datetime([c["time"] for c in candles], utc=True).tz_localize(None)
        rows = [[float(c["mid"][k]) for k in "ohlc"] for c in candles]
        return clean(pd.DataFrame(rows, index=idx, columns=COLUMNS))

    def daily(self, symbol: str, years: int = 10) -> pd.DataFrame:
        df = self._frame(symbol, "D", min(5000, years * 262))
        # a bar opens at 17:00 New York (21:00 / 22:00 UTC) of the previous calendar day;
        # stamp it with the trading day it belongs to
        df.index = (df.index + pd.Timedelta(hours=6)).normalize()
        df = df[df.index.weekday < 5]
        return df[~df.index.duplicated(keep="last")]

    def h4(self, symbol: str, days: int = 120) -> pd.DataFrame:
        return self._frame(symbol, "H4", min(5000, days * 6))


class TwelveDataProvider:
    """Twelve Data time_series API. Needs an API key (the free plan is enough).

    The key is read from the TWELVEDATA_API_KEY environment variable. Where a network proxy
    injects the Authorization header for the Twelve Data host, the variable can be left unset.
    The free plan allows 8 requests a minute, so uncached downloads are paced.
    """

    URL = "https://api.twelvedata.com/time_series"

    def __init__(self, api_key: str | None = None, cache_dir: str | os.PathLike | None = None,
                 cache_minutes: float = 30, requests_per_minute: float = 8, session=None,
                 sleep=time.sleep, clock=time.time):
        self.key = api_key or os.environ.get("TWELVEDATA_API_KEY") or "set-by-proxy"
        self.cache_dir = Path(cache_dir) if cache_dir else None
        self.cache_seconds = cache_minutes * 60
        self.gap = 60.0 / requests_per_minute + 0.3
        self._session = session
        self._sleep = sleep
        self._clock = clock
        self._fetched: dict[tuple, float] = {}   # when each response was downloaded
        self._last_call = 0.0

    def _get(self, symbol: str, interval: str, size: int) -> dict:
        cache = None
        if self.cache_dir:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            cache = self.cache_dir / f"td_{symbol}_{interval}_{size}.json"
            if cache.exists() and time.time() - cache.stat().st_mtime < self.cache_seconds:
                self._fetched[(symbol, interval)] = cache.stat().st_mtime
                return json.loads(cache.read_text())
        if self._session is None:
            import requests
            self._session = requests.Session()
        params = {"symbol": f"{symbol[:3]}/{symbol[3:]}", "interval": interval,
                  "outputsize": size, "timezone": "UTC", "order": "asc"}
        headers = {"Authorization": f"apikey {self.key}"}
        last_error: Exception | None = None
        for attempt in range(4):
            wait = self._last_call + self.gap - time.time()
            if wait > 0:
                self._sleep(wait)
            self._last_call = time.time()
            try:
                r = self._session.get(self.URL, params=params, headers=headers, timeout=30)
                payload = r.json()
                # Twelve Data reports most errors in the body, with HTTP 200
                code = payload.get("code", r.status_code) if payload.get("status") != "ok" else 200
                if code == 200:
                    self._fetched[(symbol, interval)] = self._clock()
                    if cache:
                        cache.write_text(json.dumps(payload))
                    return payload
                last_error = DataError(f"{code}: {str(payload.get('message'))[:140]}")
                if code == 429:                 # minute quota used up: wait for the next minute
                    self._sleep(61)
                    continue
                if code in (400, 401, 403, 404):
                    break
            except Exception as exc:            # network errors: retry with backoff
                last_error = exc
            self._sleep(2 ** attempt)
        raise DataError(f"{symbol} {interval}: download failed ({last_error})")

    def _frame(self, symbol: str, interval: str, size: int, closes_after: pd.Timedelta) -> pd.DataFrame:
        values = self._get(symbol, interval, size).get("values") or []
        if not values:
            raise DataError(f"{symbol}: no {interval} bars returned")
        idx = pd.to_datetime([v["datetime"] for v in values])
        rows = [[float(v[k]) for k in COLUMNS] for v in values]
        df = clean(pd.DataFrame(rows, index=idx, columns=COLUMNS))
        if interval == "1day":
            df = df[df.index.weekday < 5]
        # The last bar counts only if it had closed when the response was downloaded - a
        # cached response can hold a bar that was still forming at the time.
        fetched = pd.Timestamp(self._fetched[(symbol, interval)], unit="s")
        return drop_unfinished(df, closes_after, now=fetched)

    def daily(self, symbol: str, years: int = 10) -> pd.DataFrame:
        return self._frame(symbol, "1day", min(5000, years * 262), DAILY_CLOSE)

    def h4(self, symbol: str, days: int = 120) -> pd.DataFrame:
        return self._frame(symbol, "4h", min(5000, days * 6), pd.Timedelta(hours=4))


class CsvProvider:
    """Reads <dir>/<SYMBOL>_D1.csv and <SYMBOL>_H4.csv (time,open,high,low,close)."""

    def __init__(self, directory: str | os.PathLike):
        self.dir = Path(directory)

    def _read(self, symbol: str, tf: str) -> pd.DataFrame:
        path = self.dir / f"{symbol}_{tf}.csv"
        if not path.exists():
            raise DataError(f"{path} not found")
        df = pd.read_csv(path)
        df.columns = [c.strip().strip("<>").lower() for c in df.columns]
        if "time" not in df.columns and "date" in df.columns:
            df = df.rename(columns={"date": "time"})
        df.index = pd.to_datetime(df.pop("time"))
        return clean(df)

    def daily(self, symbol: str, years: int = 10) -> pd.DataFrame:
        df = self._read(symbol, "D1")
        df.index = df.index.normalize()
        return drop_unfinished(df, DAILY_CLOSE)

    def h4(self, symbol: str, days: int = 120) -> pd.DataFrame:
        return self._read(symbol, "H4")
