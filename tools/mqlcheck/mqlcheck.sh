#!/usr/bin/env bash
# mqlcheck.sh - g++-based syntax/type check for MQL5 source files.
#
#   tools/mqlcheck/mqlcheck.sh <file.mq5> [more.mq5 ...]
#
# Each file is pre-processed (line-preserving) into /tmp/mqlcheck/<name>.cpp
# and compiled with "g++ -std=c++17 -fsyntax-only" against the fake MQL5
# runtime in tools/mqlcheck/include. Diagnostics carry the ORIGINAL file name
# and line numbers. Exit status is non-zero when any file has errors.
#
# Environment:
#   MQLCHECK_TMPDIR       where the pre-processed .cpp files go (default /tmp/mqlcheck)
#   MQLCHECK_EXTRA_FLAGS  extra g++ flags (e.g. "-fpermissive" to downgrade the
#                         int->enum conversion error that MQL5 only warns about)
#   MQLCHECK_VERBOSE=1    print the g++ command line and resolved includes
#   MQL5_INCLUDE          extra MQL5 Include directories for #include <...>
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INC="$HERE/include"
TMP="${MQLCHECK_TMPDIR:-/tmp/mqlcheck}"
GXX="${CXX:-g++}"
EXTRA="${MQLCHECK_EXTRA_FLAGS:-}"

if [ $# -eq 0 ]; then
   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
   exit 2
fi
mkdir -p "$TMP" || exit 2

# The flag set. -fno-operator-names lets MQL5 identifiers such as "and", "or",
# "not", "xor" compile; -Wno-narrowing accepts "double a[2] = {n, m}" which is
# legal MQL5 but a C++11 narrowing error.
FLAGS=(-std=c++17 -fsyntax-only -Wall -Wextra
       -Wno-unused-parameter -Wno-unused-variable -Wno-unused-but-set-variable
       -Wno-sign-compare -Wno-unused-function
       -fno-operator-names -Wno-narrowing
       -I "$INC" -include mql5_shim.h)

status=0
for src in "$@"; do
   if [ ! -f "$src" ]; then
      echo "mqlcheck: no such file: $src" >&2
      status=1
      continue
   fi
   base="$(basename "$src")"
   cpp="$TMP/${base%.*}.cpp"
   log="$TMP/${base%.*}.log"
   if ! python3 "$HERE/preprocess.py" "$src" "$cpp"; then
      echo "mqlcheck: FAIL $src (pre-processing failed)" >&2
      status=1
      continue
   fi
   if [ -n "${MQLCHECK_VERBOSE:-}" ]; then
      echo "mqlcheck: $GXX ${FLAGS[*]} $EXTRA $cpp" >&2
   fi
   # shellcheck disable=SC2086
   "$GXX" "${FLAGS[@]}" $EXTRA "$cpp" >"$log" 2>&1
   rc=$?
   # Missing ';' is reported at the NEXT token (like MetaEditor does); point
   # at the line that most likely lacks it when that token starts a new line.
   python3 - "$log" "$src" <<'PY'
import re, sys
log, src = sys.argv[1], sys.argv[2]
try:
    lines = open(src, encoding="utf-8", errors="replace").read().split("\n")
except OSError:
    lines = []
out = []
pat = re.compile(r"^(.*):(\d+):(\d+): error: expected (?:',' or )?';' before")
for ln in open(log, encoding="utf-8", errors="replace"):
    out.append(ln.rstrip("\n"))
    m = pat.match(ln)
    if m and lines:
        n, col = int(m.group(2)), int(m.group(3))
        if col <= len(lines[n - 1]) - len(lines[n - 1].lstrip()) + 1:
            p = n - 1
            while p >= 1 and lines[p - 1].strip() == "":
                p -= 1
            if p >= 1:
                out.append("%s:%d:%d: note: the statement on this line is probably missing its ';'"
                           % (m.group(1), p, len(lines[p - 1].rstrip()) + 1))
print("\n".join(out)) if out else None
PY
   errors=$(grep -c ': error:' "$log")
   warnings=$(grep -c ': warning:' "$log")
   if [ $rc -eq 0 ]; then
      echo "mqlcheck: OK   $src  ($warnings warning(s); preprocessed: $cpp)"
   else
      echo "mqlcheck: FAIL $src  ($errors error(s), $warnings warning(s); preprocessed: $cpp)"
      status=1
   fi
done
exit $status
