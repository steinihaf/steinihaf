# mqlcheck — g++-based syntax check for MQL5 sources

There is no MetaEditor on Linux, so this harness fakes the MQL5 runtime with C++ headers
and compiles a pre-processed copy of the `.mq5` file with `g++ -std=c++17 -fsyntax-only`.

```
tools/mqlcheck/mqlcheck.sh MQL5/Experts/LineTouchEA.mq5
tools/mqlcheck/mqlcheck.sh tools/mqlcheck/samples/good.mq5 tools/mqlcheck/samples/bad.mq5
```

Diagnostics carry the original file name and line numbers (the pre-processing is
line-preserving). The exit status is non-zero when any file has errors.

## What it catches

Typos in identifiers, undeclared variables, wrong argument counts or types for built-in
functions and the Standard Library trade classes, missing semicolons, unbalanced braces,
illegal implicit conversions (for example a `double` passed where a `string` is required),
and most other things MetaEditor would reject.

## What it cannot check

MQL5 semantics the fake runtime does not model: whether an API call behaves as assumed at
run time, MetaEditor's own warnings, `#property` directives, `#resource` files, enum-to-int
conversion warnings, and anything that only shows up in the Strategy Tester or on a live
chart. A clean run is a strong hint, not a compile. Always compile in MetaEditor before use.

## Layout

```
mqlcheck.sh              driver: pre-process, compile, report
preprocess.py            line-preserving rewrite of MQL5 into C++ (see its docstring)
include/mql5_shim.h      fake MQL5 runtime: types, enums, constants, built-in functions
include/Trade/*.mqh      fake Standard Library classes (CTrade, CPositionInfo, ...)
samples/good.mq5         must pass cleanly
samples/bad.mq5          five injected errors that must all be reported
```
