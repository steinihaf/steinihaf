// mqlcheck umbrella header: fakes the MQL5 runtime API so that a
// pre-processed .mq5 file can be checked with "g++ -std=c++17 -fsyntax-only".
// Nothing here is meant to run; bodies are trivial stubs.
#pragma once
#include "mql5/types.h"
#include "mql5/enums.h"
#include "mql5/enums_chart.h"
#include "mql5/colors.h"
#include "mql5/functions_core.h"
#include "mql5/functions_market.h"
