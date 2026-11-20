import numpy as np
import pandas as pd
import pytest

from fxscan import indicators as ind
from fxscan.backtest import backtest_pair, summarize
from fxscan.data import CsvProvider, OandaProvider, TwelveDataProvider, DataError, clean, drop_unfinished, DAILY_CLOSE
from fxscan.levels import aggregate, build_levels
from fxscan.setups import PairData, WARMUP, detect, daily_trend
from fxscan.strength import strength_panel
from fxscan.universe import ALL_SYMBOLS, FX_PAIRS, instrument
from fxscan.zigzag import zigzag


def make_frame(close, wick=0.0005, start="2020-01-01"):
    close = np.asarray(close, dtype=float)
    opn = np.concatenate(([close[0]], close[:-1]))
    idx = pd.bdate_range(start, periods=len(close))
    return pd.DataFrame({"open": opn, "high": np.maximum(opn, close) + wick,
                         "low": np.minimum(opn, close) - wick, "close": close}, index=idx)


def random_walk(n=1500, seed=1, drift=0.0, vol=0.006, start=1.10):
    rng = np.random.default_rng(seed)
    return start * np.exp(np.cumsum(rng.normal(drift, vol, n)))


def test_universe():
    assert len(FX_PAIRS) == 28 and len(set(FX_PAIRS)) == 28
    assert len(ALL_SYMBOLS) == 29
    assert instrument("USDJPY").pip == 0.01 and instrument("EURUSD").pip == 0.0001
    assert instrument("XAUUSD").is_fx is False
    with pytest.raises(ValueError):
        instrument("EUR")


def test_ema_and_atr_basics():
    x = np.full(50, 2.0)
    assert np.allclose(ind.ema(x, 20)[19:], 2.0)
    assert np.isnan(ind.ema(x, 20)[:19]).all()
    h, l, c = np.full(40, 1.01), np.full(40, 0.99), np.full(40, 1.0)
    assert np.allclose(ind.atr(h, l, c)[14:], 0.02)


def test_rsi_extremes():
    up = np.linspace(1, 2, 60)
    assert ind.rsi(up)[-1] == 100.0
    assert ind.rsi(up[::-1])[-1] == pytest.approx(0.0)


def test_adx_trend_vs_chop():
    n = 300
    trend = np.linspace(1.0, 1.5, n)
    a_trend = ind.adx(trend + 0.002, trend - 0.002, trend)[-1]
    chop = 1.0 + 0.002 * np.sin(np.arange(n))
    a_chop = ind.adx(chop + 0.002, chop - 0.002, chop)[-1]
    assert a_trend > 40 > a_chop


def test_indicators_are_causal():
    c = random_walk(400)
    df = make_frame(c)
    h, l = df["high"].to_numpy(), df["low"].to_numpy()
    for f in (lambda k: ind.ema(c[:k], 50), lambda k: ind.atr(h[:k], l[:k], c[:k]),
              lambda k: ind.rsi(c[:k]), lambda k: ind.adx(h[:k], l[:k], c[:k])):
        assert np.allclose(f(400)[:300], f(300), equal_nan=True)


def test_zigzag_finds_alternating_swings():
    x = np.concatenate([np.linspace(1.0, 1.2, 40), np.linspace(1.2, 1.05, 40),
                        np.linspace(1.05, 1.3, 40), np.linspace(1.3, 1.1, 40)])
    piv = zigzag(x + 0.001, x - 0.001)
    assert [p.is_peak for p in piv] == [not piv[0].is_peak if i % 2 else piv[0].is_peak
                                        for i in range(len(piv))]
    peaks = [p.price for p in piv if p.is_peak]
    assert any(abs(p - 1.201) < 1e-6 for p in peaks) and any(abs(p - 1.301) < 1e-6 for p in peaks)
    troughs = [p.price for p in piv if not p.is_peak]
    assert any(abs(t - 1.049) < 1e-6 for t in troughs)


def test_zigzag_short_input():
    assert zigzag(np.ones(5), np.ones(5)) == []


def test_aggregate():
    keys = np.array([1, 1, 2, 2, 2, 3])
    hi, lo = aggregate(keys, np.array([1., 3, 2, 5, 4, 9]), np.array([0., 1, 1, 2, 0.5, 7]))
    assert hi.tolist() == [3, 5, 9] and lo.tolist() == [0, 0.5, 7]


def test_levels_merge_and_grade():
    df = make_frame(random_walk(1500, seed=3))
    p = PairData.from_frame("EURUSD", df)
    t = len(p) - 1
    lv = p.levels_at(t)
    assert lv, "expected some levels"
    prices = [x.price for x in lv]
    assert prices == sorted(prices)
    gaps = np.diff(prices)
    assert (gaps > 0.25 * p.atr[t] - 1e-12).all()
    assert {x.grade for x in lv} <= {"A", "B"}


def test_strength_signs():
    idx = pd.bdate_range("2024-01-01", periods=60)
    closes = pd.DataFrame({"EURUSD": np.linspace(1.0, 1.1, 60), "USDJPY": np.linspace(150, 140, 60),
                           "EURJPY": np.full(60, 155.0)}, index=idx)
    atrs = pd.DataFrame({"EURUSD": 0.005, "USDJPY": 0.8, "EURJPY": 0.9}, index=idx)
    last = strength_panel(closes, atrs).iloc[-1]
    assert last["USD"] < 0 < last["EUR"] and last["JPY"] > 0


def test_clean():
    idx = pd.bdate_range("2024-01-01", periods=30)
    df = pd.DataFrame({"open": 1.0, "high": 1.001, "low": 0.999, "close": 1.0}, index=idx)
    df.iloc[10, df.columns.get_loc("close")] = np.nan
    df.iloc[20, df.columns.get_loc("high")] = 0.9995    # high below the open
    out = clean(df)
    assert idx[10] not in out.index and len(out) == 29
    assert (out["high"] >= out[["open", "close"]].max(axis=1)).all()


class FakeResponse:
    def __init__(self, status, payload):
        self.status_code, self._payload, self.text = status, payload, str(payload)

    def json(self):
        return self._payload


class FakeSession:
    def __init__(self, response):
        self.response, self.calls = response, []

    def get(self, url, **kw):
        self.calls.append((url, kw))
        return self.response


def test_oanda_provider_parses_candles():
    candles = [
        {"complete": True, "time": "2026-11-17T22:00:00.000000000Z",
         "mid": {"o": "1.1000", "h": "1.1050", "l": "1.0950", "c": "1.1020"}},
        {"complete": True, "time": "2026-11-18T22:00:00.000000000Z",
         "mid": {"o": "1.1020", "h": "1.1080", "l": "1.1010", "c": "1.1070"}},
        {"complete": False, "time": "2026-11-19T22:00:00.000000000Z",
         "mid": {"o": "1.1070", "h": "1.1075", "l": "1.1060", "c": "1.1065"}},
    ]
    ses = FakeSession(FakeResponse(200, {"candles": candles}))
    df = OandaProvider(token="t", session=ses).daily("EURUSD")
    assert [str(d.date()) for d in df.index] == ["2026-11-18", "2026-11-19"]   # trading days
    assert df["close"].tolist() == [1.102, 1.107]                              # forming bar dropped
    url, kw = ses.calls[0]
    assert url.endswith("/v3/instruments/EUR_USD/candles")
    assert kw["headers"]["Authorization"] == "Bearer t" and kw["params"]["granularity"] == "D"


def test_oanda_provider_reports_auth_failure():
    ses = FakeSession(FakeResponse(401, {"errorMessage": "Insufficient authorization"}))
    with pytest.raises(DataError, match="401"):
        OandaProvider(token="bad", session=ses).daily("EURUSD")
    assert len(ses.calls) == 1      # no pointless retries


def test_twelvedata_provider_parses_and_drops_forming_bar():
    today = pd.Timestamp.now(tz="UTC").tz_localize(None).normalize()
    days = pd.bdate_range(end=today + pd.Timedelta(days=3), periods=6)   # last ones are in the future
    values = [{"datetime": str(d.date()), "open": "1.1", "high": "1.2", "low": "1.0", "close": "1.15"}
              for d in days]
    ses = FakeSession(FakeResponse(200, {"status": "ok", "values": values}))
    df = TwelveDataProvider(api_key="k", session=ses, sleep=lambda s: None).daily("EURUSD")
    assert 1 <= len(df) < 6 and df.index[-1] <= today
    url, kw = ses.calls[0]
    assert kw["params"]["symbol"] == "EUR/USD" and kw["headers"]["Authorization"] == "apikey k"


def test_twelvedata_provider_error_in_body():
    ses = FakeSession(FakeResponse(200, {"status": "error", "code": 401, "message": "bad key"}))
    with pytest.raises(DataError, match="401"):
        TwelveDataProvider(api_key="k", session=ses, sleep=lambda s: None).daily("EURUSD")
    assert len(ses.calls) == 1


def test_csv_provider_roundtrip(tmp_path):
    df = make_frame(random_walk(50))
    df.rename_axis("time").to_csv(tmp_path / "EURUSD_D1.csv")
    out = CsvProvider(tmp_path).daily("EURUSD")
    assert len(out) == 50 and out["close"].iloc[-1] == pytest.approx(df["close"].iloc[-1])
    with pytest.raises(DataError):
        CsvProvider(tmp_path).daily("GBPUSD")


def test_drop_unfinished():
    idx = pd.to_datetime(["2026-11-18", "2026-11-19", "2026-11-20"])
    df = pd.DataFrame({"open": 1.0, "high": 1.0, "low": 1.0, "close": 1.0}, index=idx)
    assert len(drop_unfinished(df, DAILY_CLOSE, pd.Timestamp("2026-11-20 18:00"))) == 2
    assert len(drop_unfinished(df, DAILY_CLOSE, pd.Timestamp("2026-11-20 22:30"))) == 3


def uptrend_with_pullback():
    """A steady uptrend, a three-bar dip to the EMA20, then a strong up bar."""
    n = 400
    c = list(1.0 + 0.0015 * np.arange(n))
    for step in (-0.005, -0.005, -0.004):
        c.append(c[-1] + step)
    c.append(c[-1] + 0.007)
    return make_frame(c, wick=0.001)


def test_pullback_setup_detected():
    df = uptrend_with_pullback()
    p = PairData.from_frame("EURUSD", df)
    t = len(p) - 1
    assert daily_trend(p, t) == 1
    s = detect(p, t)
    assert s is not None and s.kind == "pullback" and s.direction == 1
    assert s.stop < s.entry < s.target
    assert (s.target - s.entry) == pytest.approx(2 * (s.entry - s.stop), abs=2e-5)
    assert detect(p, t - 1) is None      # no trigger while the dip is still falling


def test_pullback_mirror_short():
    df = uptrend_with_pullback()
    inv = 3.0 - df
    inv = inv.rename(columns={"high": "low", "low": "high"})[["open", "high", "low", "close"]]
    p = PairData.from_frame("EURUSD", inv)
    s = detect(p, len(p) - 1)
    assert s is not None and s.direction == -1 and s.target < s.entry < s.stop


def test_detect_has_no_lookahead():
    df = make_frame(random_walk(900, seed=7), wick=0.002)
    full = PairData.from_frame("EURUSD", df)
    hits = 0
    for t in range(WARMUP, 880, 7):
        cut = PairData.from_frame("EURUSD", df.iloc[:t + 1])
        a, b = detect(full, t), detect(cut, t)
        assert (a is None) == (b is None)
        if a:
            hits += 1
            assert a.to_dict() == b.to_dict()
    assert hits >= 0


def test_backtest_trade_accounting():
    df = uptrend_with_pullback()
    # continue the trend so the 2R target is reached
    last = df["close"].iloc[-1]
    ext = make_frame(last + 0.003 * np.arange(1, 30), wick=0.001,
                     start=str((df.index[-1] + pd.offsets.BDay(1)).date()))
    ext.iloc[0, ext.columns.get_loc("open")] = last
    p = PairData.from_frame("EURUSD", pd.concat([df, ext]))
    trades = [t for t in backtest_pair(p) if t.signal_date == str(df.index[-1].date())]
    assert len(trades) == 1
    tr = trades[0]
    assert tr.outcome == "target" and tr.direction == 1
    assert 1.5 < tr.r < 2.6          # entered at the next open, so not exactly 2R; spread charged


def test_backtest_stop_before_target_in_same_bar():
    df = uptrend_with_pullback()
    last = df["close"].iloc[-1]
    nxt = (df.index[-1] + pd.offsets.BDay(1))
    wild = pd.DataFrame({"open": [last], "high": [last + 0.5], "low": [last - 0.5], "close": [last]},
                        index=[nxt])
    tail = make_frame(np.full(5, last), start=str((nxt + pd.offsets.BDay(1)).date()))
    p = PairData.from_frame("EURUSD", pd.concat([df, wild, tail]))
    tr = [t for t in backtest_pair(p) if t.signal_date == str(df.index[-1].date())][0]
    assert tr.outcome == "stop" and tr.r < -1.0


def test_summarize():
    s = summarize([2, -1, -1, 2, -1])
    assert s["trades"] == 5 and s["win_rate"] == 0.4 and s["total_r"] == 1.0
    assert s["profit_factor"] == pytest.approx(1.33, abs=0.01) and s["max_drawdown_r"] == 2.0
    assert summarize([]) == {"trades": 0}
