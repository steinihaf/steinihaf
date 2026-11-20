# Project skills

These nine skills are copied unmodified from
[tradermonty/claude-trading-skills](https://github.com/tradermonty/claude-trading-skills)
at commit 9019854 (MIT licence, see `LICENSE-tradermonty`). The upstream repository
holds 74 skills; only the ones useful for forex swing trading and MetaTrader work are here.

| Skill | Use | Needs |
|---|---|---|
| backtest-expert | Method for stress-testing a strategy and avoiding overfitting | nothing |
| trade-hypothesis-ideator | Turns data and trade logs into falsifiable strategy hypotheses | nothing |
| technical-analyst | Weekly chart analysis from chart images (forex included) | nothing for images; FMP key for its price script |
| market-environment-analysis | Global risk-on / risk-off report including forex | web search |
| market-news-analyst | Impact of recent market-moving news | web search |
| fxmacrodata-calendar | Macro release calendar (CPI, NFP, central banks) | `FXMACRODATA_API_KEY` |
| economic-calendar-fetcher | Economic calendar for the coming days | `FMP_API_KEY` |
| cot-contrarian-detector | Crowded speculative positioning from CFTC reports, FX futures included | `FMP_API_KEY` |
| mt5-robot-tester | Batch-runs Expert Advisors through the MT5 Strategy Tester | Windows with MetaTrader 5 |
