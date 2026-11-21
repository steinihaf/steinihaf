import json
import types

import numpy as np
import pandas as pd
import pytest

from fxbot.brain import Brain
from fxbot.broker import PaperBroker
from fxbot.config import Config
from fxbot.engine import Engine
from fxbot.models import Account, CloseTrade, Decision, MoveStop, OpenTrade, Position, Quote
from fxbot.risk import RiskManager
from fxscan.data import CsvProvider

SYMS = ["EURUSD", "GBPUSD", "AUDUSD", "USDJPY", "EURGBP"]
START = {"EURUSD": 1.10, "GBPUSD": 1.30, "AUDUSD": 0.68, "USDJPY": 150.0, "EURGBP": 0.85}


@pytest.fixture(scope="module")
def csv_dir(tmp_path_factory):
    d = tmp_path_factory.mktemp("bars")
    rng = np.random.default_rng(5)
    idx = pd.bdate_range(end="2026-11-19", periods=600)
    for s in SYMS:
        c = START[s] * np.exp(np.cumsum(rng.normal(0, 0.005, len(idx))))
        o = np.concatenate(([c[0]], c[:-1]))
        w = 0.003 * c
        pd.DataFrame({"open": o, "high": np.maximum(o, c) + w, "low": np.minimum(o, c) - w, "close": c},
                     index=idx).rename_axis("time").to_csv(d / f"{s}_D1.csv")
    return d


class ScriptedBrain:
    def __init__(self, make):
        self.make, self.calls = make, []

    def decide(self, snapshot):
        self.calls.append(snapshot)
        return self.make(snapshot)


def engine(csv_dir, tmp_path, make, demo=True, dry_run=False, balance=10_000.0, **cfg_kw):
    cfg = Config(state_dir=str(tmp_path / "state"), symbols=",".join(SYMS), **cfg_kw)
    broker = PaperBroker(CsvProvider(csv_dir), balance=balance, demo=demo)
    brain = ScriptedBrain(make)
    return Engine(cfg, broker, brain, dry_run=dry_run, log=lambda m: None), broker, brain


def long_trade(broker, symbol="EURUSD", atr_mult=1.5, risk=0.5, snapshot=None):
    """A long with a stop `atr_mult` daily ATRs below the price."""
    from fxscan.setups import PairData
    p = PairData.from_frame(symbol, broker.provider.daily(symbol))
    q = broker.quote(symbol)
    stop = q.ask - atr_mult * float(p.atr[-1])
    return OpenTrade(symbol=symbol, direction="long", stop=stop, target=None, risk_pct=risk, reason="test")


def decide_open(broker, **kw):
    return lambda snap: Decision(market_view="t", opens=[long_trade(broker, **kw)], closes=[], stop_moves=[])


def test_refuses_non_demo_account_without_calling_claude(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, lambda s: pytest.fail("must not be called"), demo=False)
    entry = eng.cycle("daily")
    assert "not a demo account" in entry["skipped"]
    assert brain.calls == [] and broker.positions() == []


def test_opens_a_trade_sized_from_risk(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    brain.make = decide_open(broker)
    entry = eng.cycle("daily")
    pos = broker.positions()
    assert len(pos) == 1 and pos[0].symbol == "EURUSD" and pos[0].direction == 1
    loss = broker.loss_per_lot("EURUSD", 1, pos[0].entry, pos[0].stop) * pos[0].volume
    assert 0 < loss <= 50.0 + 1e-6            # 0.5% of 10,000
    assert loss > 35.0                        # and not needlessly small
    assert "open EURUSD long" in entry["results"][0]
    assert brain.calls[0]["new_trades_allowed"] is True


def test_risk_pct_is_capped(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    brain.make = decide_open(broker, risk=25.0)          # absurd request
    eng.cycle("daily")
    p = broker.positions()[0]
    assert broker.loss_per_lot("EURUSD", 1, p.entry, p.stop) * p.volume <= 50.0 + 1e-6


@pytest.mark.parametrize("mult, why", [(0.2, "outside"), (6.0, "outside"), (-1.0, "wrong side")])
def test_bad_stops_are_dropped(csv_dir, tmp_path, mult, why):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    brain.make = decide_open(broker, atr_mult=mult)
    entry = eng.cycle("daily")
    assert broker.positions() == [] and why in entry["results"][0]


def test_manage_cycle_never_opens(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    brain.make = decide_open(broker)
    eng.cycle("daily")
    brain.make = decide_open(broker, symbol="USDJPY")
    entry = eng.cycle("manage")
    assert len(broker.positions()) == 1
    assert "not allowed in this cycle" in entry["results"][0]
    assert brain.calls[-1]["new_trades_allowed"] is False


def test_manage_cycle_with_nothing_open_does_not_call_claude(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, lambda s: pytest.fail("must not be called"))
    eng.cycle("manage")
    assert brain.calls == []


def test_dry_run_sends_nothing(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None, dry_run=True)
    brain.make = decide_open(broker)
    entry = eng.cycle("daily")
    assert broker.positions() == [] and entry["results"][0].startswith("DRY RUN")


def test_stop_file_blocks_new_trades(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    (eng.dir / "STOP").write_text("")
    brain.make = decide_open(broker)
    entry = eng.cycle("daily")
    assert broker.positions() == [] and brain.calls[0]["why_not"] == "STOP file present"


def test_daily_loss_stop(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    broker.loss_today = 250.0                               # 2.5% of balance
    brain.make = decide_open(broker)
    eng.cycle("daily")
    assert broker.positions() == [] and "today's loss" in brain.calls[0]["why_not"]


def test_drawdown_halt_is_remembered(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    brain.make = lambda s: Decision.nothing("x")
    eng.cycle("daily")                                      # records the starting equity
    broker._acct.equity = 8_900.0                           # -11%
    eng.cycle("daily")
    broker._acct.equity = 10_000.0                          # recovers, but stays halted
    brain.make = decide_open(broker)
    eng.cycle("daily")
    assert broker.positions() == [] and eng.load_state()["halted"] is True


def test_only_own_positions_and_tightening_stops(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, None)
    brain.make = decide_open(broker)
    eng.cycle("daily")
    p = broker.positions()[0]
    looser, tighter = p.stop - 0.01, p.stop + 0.002
    brain.make = lambda s: Decision(market_view="t", opens=[], closes=[CloseTrade(ticket=999, reason="x")],
                                    stop_moves=[MoveStop(ticket=p.ticket, new_stop=looser, reason="x"),
                                                MoveStop(ticket=p.ticket, new_stop=tighter, reason="x")])
    entry = eng.cycle("manage")
    assert "not one of the bot's" in entry["results"][0]
    assert "only be moved to reduce risk" in entry["results"][1]
    assert broker.positions()[0].stop == pytest.approx(tighter)
    brain.make = lambda s: Decision(market_view="t", opens=[], stop_moves=[],
                                    closes=[CloseTrade(ticket=p.ticket, reason="done")])
    eng.cycle("manage")
    assert broker.positions() == []


def test_journal_and_recent_decisions(csv_dir, tmp_path):
    eng, broker, brain = engine(csv_dir, tmp_path, lambda s: Decision.nothing("quiet day"))
    eng.cycle("daily")
    eng.cycle("daily")
    lines = (eng.dir / "journal.jsonl").read_text().splitlines()
    assert len(lines) == 2 and json.loads(lines[0])["decision"]["market_view"] == "quiet day"
    assert brain.calls[1]["your_recent_decisions"][0]["market_view"] == "quiet day"


# ---- RiskManager directly -------------------------------------------------------------------
ACCT = Account(1, "x", "USD", 10_000.0, 10_000.0, True)
Q = Quote(1.1000, 1.1001, 0.01, 0.01, 100.0, 5)


def _pos(symbol, ticket=1, d=1):
    return Position(ticket, symbol, d, 0.1, 1.0, 0.99, None, 0.0, "")


def _open(**kw):
    base = dict(symbol="EURUSD", direction="long", stop=1.0900, target=None, risk_pct=0.5, reason="")
    return OpenTrade(**{**base, **kw})


def check(trade, positions=(), open_risk=0.0, quote=Q, loss_per_lot=1010.0, cfg=None):
    return RiskManager(cfg or Config()).check_open(trade, ACCT, list(positions), open_risk, quote,
                                                   0.0080, loss_per_lot)


def test_risk_volume_rounds_down():
    v = check(_open())                    # 50 USD / 1010 per lot = 0.0495 -> 0.04
    assert v.ok and v.volume == 0.04 and v.risk_money == pytest.approx(40.4)


def test_risk_refuses_when_min_lot_is_too_big():
    v = check(_open(), loss_per_lot=6000.0)
    assert not v.ok and "smallest lot" in v.reason


def test_risk_position_and_currency_caps():
    assert "already holding" in check(_open(), [_pos("EURUSD")]).reason
    assert "involving USD" in check(_open(), [_pos("GBPUSD"), _pos("AUDUSD", 2)]).reason
    four = [_pos("GBPJPY"), _pos("AUDCAD", 2), _pos("NZDCHF", 3), _pos("CADJPY", 4)]
    assert "open positions" in check(_open(), four).reason


def test_risk_total_budget_and_spread_and_universe():
    assert "open risk already" in check(_open(), open_risk=200.0).reason
    v = check(_open(), open_risk=180.0)                 # only 20 USD of budget left
    assert not v.ok or v.risk_money <= 20.0
    wide = Quote(1.1000, 1.1010, 0.01, 0.01, 100.0, 5)  # 10 pips
    assert "spread" in check(_open(), quote=wide).reason
    assert "universe" in check(_open(symbol="BTCUSD")).reason


def test_risk_target_and_nonsense_numbers():
    assert "target" in check(_open(target=1.1050)).reason          # less than 1R away
    assert check(_open(target=1.1300)).ok
    assert not check(_open(risk_pct=-1)).ok
    assert not check(_open(stop=float("nan"))).ok


def test_config_rejects_unknown_and_unsafe_settings(tmp_path):
    f = tmp_path / "fxbot.toml"
    f.write_text("max_risk_per_trade_pct = 5.0\n")
    with pytest.raises(ValueError):
        Config.load(f)
    f.write_text("leverage_boost = 3\n")
    with pytest.raises(ValueError, match="unknown setting"):
        Config.load(f)
    f.write_text("max_positions = 2\nsymbol_suffix = \".m\"\n")
    cfg = Config.load(f)
    assert cfg.max_positions == 2 and cfg.symbol_suffix == ".m"


# ---- Brain ----------------------------------------------------------------------------------
class FakeMessages:
    def __init__(self, response=None, error=None):
        self.response, self.error, self.kwargs = response, error, None

    def parse(self, **kwargs):
        self.kwargs = kwargs
        if self.error:
            raise self.error
        return self.response


def _client(response=None, error=None):
    return types.SimpleNamespace(messages=FakeMessages(response, error))


def test_brain_returns_parsed_decision_and_sends_the_snapshot():
    want = Decision.nothing("flat")
    client = _client(types.SimpleNamespace(stop_reason="end_turn", parsed_output=want))
    got = Brain(Config(), client).decide({"account": {"balance": 1}})
    assert got is want
    kw = client.messages.kwargs
    assert kw["model"] == "claude-opus-5-5" and kw["output_format"] is Decision
    assert '"balance": 1' in kw["messages"][0]["content"] and "DEMO" in kw["system"]


@pytest.mark.parametrize("stop_reason", ["refusal", "max_tokens"])
def test_brain_does_nothing_on_refusal_or_truncation(stop_reason):
    client = _client(types.SimpleNamespace(stop_reason=stop_reason, parsed_output=None))
    d = Brain(Config(), client).decide({})
    assert d.opens == [] and d.closes == [] and "no decision" in d.market_view


def test_brain_does_nothing_when_the_api_is_unreachable():
    import anthropic
    err = Exception.__new__(anthropic.APIConnectionError)     # built without a real HTTP request
    d = Brain(Config(), _client(error=err)).decide({})
    assert d.opens == [] and "could not reach" in d.market_view
