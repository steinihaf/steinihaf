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

## From agiprolabs/claude-trading-skills

These twelve skills are copied unmodified from
[agiprolabs/claude-trading-skills](https://github.com/agiprolabs/claude-trading-skills)
at commit 981e1d7 (MIT licence, see `LICENSE-agiprolabs`). The upstream repository holds
68 skills, mostly for crypto, Solana and prediction markets; only the asset-agnostic ones
are here. Their examples are written for crypto (some demo scripts fetch sample data from
Birdeye or CoinGecko), but the methods apply to forex bars unchanged.

| Skill | Use |
|---|---|
| walk-forward-validation | Time-ordered train/test splits and overfit detection |
| regime-detection | Trend / range / volatility regime identification |
| volatility-modeling | GARCH, EWMA, realized volatility, volatility cones |
| correlation-analysis | Rolling and regime-dependent correlation, clustering |
| mean-reversion | Hurst exponent, half-life, z-score signals |
| strategy-framework | Template for writing a strategy down completely |
| exit-strategies | Stop, take-profit and trailing-stop methods |
| position-sizing | Fixed-fractional, volatility-adjusted and Kelly sizing |
| risk-management | Drawdown limits, exposure limits, circuit breakers |
| trade-journal | Trade logging and performance review |
| ohlcv-processing | Resampling, gap handling, anomaly detection in price bars |
| portfolio-analytics | Return and risk metrics, rolling analysis |
