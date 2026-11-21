# fxbot — demo-account autopilot

Once a day after the daily close, the bot scans the 28 forex pairs and gold with `fxscan`
on your broker's own bars, sends the picture to Claude, and places what Claude decides in
MetaTrader 5. While trades are open it checks in every four hours to manage them.

**It only trades demo accounts.** On any other account it refuses before doing anything,
and there is no setting to change that.

**Expect it to lose or break even.** The scanner's setups did not beat costs in ten years
of history (`../research/FINDINGS.md`), and there is no evidence that an AI choosing among
them does better. This is an experiment to watch on demo money, not a proven system.

## What decides what

| Part | Decides |
|---|---|
| `fxscan` (rules) | which pairs completed a setup, the levels, currency strength |
| Claude | which setups to take, stop and target, when to close or tighten a stop |
| `fxbot/risk.py` (code) | position size, and whether each proposal is allowed at all |

Limits enforced in code, whatever Claude answers (defaults; change them in `fxbot.toml`):

| Limit | Default |
|---|---|
| Risk per trade | 0.5% of balance (hard maximum 2%) |
| Total open risk | 2% of balance |
| Open positions | 4, and at most 2 sharing a currency |
| Stop distance | 0.5 to 4 daily ATR from the price |
| Daily loss stop | no new trades after losing 2% in a day |
| Drawdown halt | stops opening trades for good at 10% below the starting equity |
| Spread | entry skipped when the spread is over 3x the usual |
| Stops | can only be moved to reduce risk |
| Ownership | only touches positions it opened itself (magic number 20261121) |

Lot size is always calculated by the code from the risk and the stop distance.

## Setup (Windows PC with MetaTrader 5)

1. Get the code: download or clone this repository, open a Command Prompt in the
   `scanner` folder.
2. Install the packages (use the Python that has MetaTrader5 installed):
   ```
   py -3.14 -m pip install anthropic pandas numpy MetaTrader5
   ```
3. Create an Anthropic API key at <https://console.anthropic.com> and store it for your
   Windows user (then open a NEW Command Prompt):
   ```
   setx ANTHROPIC_API_KEY "your-key-here"
   ```
4. Open MetaTrader 5, log in to the **demo** account, and switch on the **Algo Trading**
   button in the toolbar.

## Run it

```
py -3.14 -m fxbot check            connection test: account, demo status, symbol names. No AI, no orders.
py -3.14 -m fxbot once --dry-run   one full cycle with Claude; logs what it WOULD do, sends nothing.
py -3.14 -m fxbot once             one real cycle.
py -3.14 -m fxbot run              the autopilot: leave this window open.
```

Do them in that order. `run` needs the PC on, MetaTrader open and the window left running;
it waits 75 minutes after the daily close before trading because spreads are wide at
rollover.

If your broker adds a suffix to symbol names (for example `EURUSD.m`), `check` usually
finds it; otherwise create `scanner/fxbot.toml` with `symbol_suffix = ".m"`.

## Watching and stopping it

* Every cycle is appended to `scanner/bot_state/journal.jsonl`: what the scanner found,
  what Claude said and why, and what happened to each proposal.
* **Pause new trades:** create an empty file named `STOP` in `scanner/bot_state/`. Open
  trades are still managed. Delete the file to resume.
* **Stop completely:** press Ctrl+C in the window. Open positions keep their stop-loss and
  take-profit in MetaTrader; close them by hand if you want out.
* After a drawdown halt, delete `scanner/bot_state/state.json` to start over.

## Cost

One Claude call per day, plus one every four hours while trades are open. With the default
model (`claude-opus-5-5`) that is roughly 10 to 50 US cents a day; a cheaper model can be
set with `model = "..."` in `fxbot.toml`.

## What has and has not been tested

The risk limits, the trading cycle, the journal and the Claude step are covered by the
test suite using a simulated broker and a scripted Claude. The MetaTrader connection
(`MT5Broker` in `broker.py`) and the live Claude call have **not** been run: they were
written on Linux, where MetaTrader does not exist. That is why the first three commands
above come before `run`.
