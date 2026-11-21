# MCP servers for this project

Two servers give Claude live market tools. Neither can be installed from a cloud
session: Twelve Data is connected in your claude.ai account, and the MetaTrader server
has to run on the Windows PC where MetaTrader 5 is installed.

## 1. Twelve Data (live prices and indicators in any Claude chat)

1. Open <https://claude.ai/customize/connectors>.
2. Find **Twelve Data**, choose **Connect**, and sign in with your Twelve Data account.
3. Start a new chat or session. Connectors are read when a session starts.

The scanner in `scanner/` does not need this connector; it calls the Twelve Data API
directly with the key saved on the cloud environment.

## 2. MetaTrader 5 (Claude reads your own terminal)

This uses [`mt5-trading-mcp`](https://github.com/vincentwongso/mt5-trading-mcp) (MIT).
It talks to the MT5 terminal that is already logged in, so no broker password goes into
any config file. It was chosen over `metatrader-mcp-server` because that one needs the
account password in the config and has no approval step for orders.

**Start on a demo account.** Out of the box this server lets an agent place real orders
without asking. Steps 3 and 4 below turn that off; do not skip them.

### Step 1 - install (Windows, in a terminal)

```
pip install mt5-trading-mcp
```

Needs Python 3.10 or newer.

### Step 2 - check it can see the terminal

Open MetaTrader 5 and log in to your account, then run:

```
python -m mt5_mcp doctor
```

Expect `[INFO] backend: native` and `[PASS]` lines.

### Step 3 - turn on the guardrails

Create `%APPDATA%\mt5-mcp\config.toml`:

```toml
[policy]
auto_approve_notional = "0.01"      # any order at or above this size needs your approval
max_notional_per_trade = "2000.00"  # hard cap per order; no approval can override it
max_daily_loss = "100.00"           # no new orders once the day's realised loss reaches this
max_orders_per_minute = 2

[symbols]
allowlist = []                      # e.g. ["EURUSD", "XAUUSD"] to restrict what can be traded
```

The amounts are in your account currency. Set them to numbers you are comfortable with.
With `auto_approve_notional` left at its default of `0`, orders execute with no approval.

### Step 4 - register it with Claude, read-only

**Claude Code** (run inside your local clone of this repository):

```
claude mcp add --transport stdio --scope project mt5-mcp -- python -m mt5_mcp serve
```

Then put the read tools on the allowlist in `.claude/settings.json`. The four order tools
(`place_order`, `modify_order`, `cancel_order`, `close_position`) are left off it, so
Claude has to ask you each time before using one:

```json
{
  "permissions": {
    "allow": [
      "mcp__mt5-mcp__ping",
      "mcp__mt5-mcp__get_terminal_info",
      "mcp__mt5-mcp__get_account_info",
      "mcp__mt5-mcp__get_quote",
      "mcp__mt5-mcp__get_symbols",
      "mcp__mt5-mcp__get_market_hours",
      "mcp__mt5-mcp__get_rates",
      "mcp__mt5-mcp__calc_margin",
      "mcp__mt5-mcp__get_positions",
      "mcp__mt5-mcp__get_orders",
      "mcp__mt5-mcp__get_history"
    ]
  }
}
```

To block orders outright instead of being asked, add a `"deny"` list with
`mcp__mt5-mcp__place_order`, `mcp__mt5-mcp__modify_order`, `mcp__mt5-mcp__cancel_order`
and `mcp__mt5-mcp__close_position`.

Do not commit the `.mcp.json` that `claude mcp add --scope project` creates: cloud
sessions on this repository run on Linux without MetaTrader and could not start it.

**Claude Desktop**: add this to `%APPDATA%\Claude\claude_desktop_config.json` and restart
the app:

```json
{
  "mcpServers": {
    "mt5-mcp": { "command": "python", "args": ["-m", "mt5_mcp", "serve"] }
  }
}
```

### Step 5 - try it

Ask Claude: "Ping MT5 and show my account balance and open positions."

### What Claude can then do

| Read tools (no approval needed) | Order tools (approval needed after steps 3-4) |
|---|---|
| account, quotes, symbols, market hours, positions, pending orders, deal history, OHLC bars, margin estimate, chart screenshot | place, modify and cancel orders, close positions |

With `get_rates`, the scanner's levels and setups can be checked against your broker's
own bars rather than Twelve Data's.

These steps follow the package's documentation at commit `2fd0ea7` (20 Nov 2026). They
have not been run on a Windows machine from this repository.
