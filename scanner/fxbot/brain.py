"""The decision step: one Claude call per cycle, returning a validated Decision."""
from __future__ import annotations

import json

from .config import Config
from .models import Decision

SYSTEM = """You manage a small forex and gold swing-trading book on a DEMO account. \
You are called once after each daily close, and every few hours while trades are open.

Each call gives you a JSON snapshot: the account, the bot's open positions, the setups a \
rules-based scanner found on the last completed daily bar, a watchlist, currency strength, \
and your own recent decisions.

What you should know about the scanner's setups: replayed over ten years of history they \
did not beat costs, and their score did not predict outcomes. Treat them as a list of pairs \
at interesting places, not as trade signals. Add your own judgment: how the setups relate \
to each other, whether several are the same bet on one currency, whether the trend, the \
level and the strength picture agree, and whether the reward is worth the risk. Taking no \
trade is a perfectly good decision, and usually the right one when nothing stands out.

Rules the software enforces whatever you answer - proposals outside them are dropped:
- Position size is computed by the software from your risk_pct and stop; you never give lots.
- Risk per trade, total open risk, number of positions and positions per currency are capped \
(the limits are in the snapshot). Stops must be between the stated ATR bounds from the price.
- A stop can only be moved to reduce risk. You can only close or change positions listed in \
the snapshot. New trades are only accepted when "new_trades_allowed" is true.
- Symbols must come from the snapshot's setups or watchlist.

Prices in the snapshot are from the last completed daily bar; your entries fill at the \
current market price, so place stops with that in mind (the setups list a reference stop).

Keep reasons short and concrete. Say plainly in market_view when you are doing nothing and why."""


class Brain:
    def __init__(self, cfg: Config, client=None):
        self.cfg = cfg
        self._client = client

    def decide(self, snapshot: dict) -> Decision:
        import anthropic
        if self._client is None:
            self._client = anthropic.Anthropic()
        try:
            resp = self._client.messages.parse(
                model=self.cfg.model,
                max_tokens=16000,
                system=SYSTEM,
                messages=[{"role": "user", "content": json.dumps(snapshot, indent=1, default=str)}],
                output_format=Decision,
                output_config={"effort": self.cfg.effort},
            )
        except anthropic.AuthenticationError as exc:
            return Decision.nothing(f"no decision: the Anthropic API key was rejected ({exc})")
        except anthropic.RateLimitError as exc:
            return Decision.nothing(f"no decision: rate limited ({exc})")
        except anthropic.APIStatusError as exc:
            return Decision.nothing(f"no decision: API error {exc.status_code}")
        except anthropic.APIConnectionError as exc:
            return Decision.nothing(f"no decision: could not reach the API ({exc})")
        if resp.stop_reason == "refusal":
            return Decision.nothing("no decision: the model declined to answer")
        if resp.stop_reason == "max_tokens" or resp.parsed_output is None:
            return Decision.nothing(f"no decision: incomplete answer ({resp.stop_reason})")
        return resp.parsed_output
