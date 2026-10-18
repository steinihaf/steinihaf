#!/usr/bin/env python3
r"""
mqlcheck pre-processor: rewrites an MQL5 source file into a C++ translation
unit that compiles against tools/mqlcheck/include/mql5_shim.h.

The rewrite is strictly LINE-PRESERVING: no line is ever inserted or deleted
(lines are blanked instead) and a `#line 1 "<orig>"` directive is emitted
first, so every g++ diagnostic carries the original file name and line number.

Per-line transformations (applied to code only - never inside strings or
comments):
  1. `#property ...`, `#import ...`, `#resource ...`     -> blank line
  2. `input group "..."`                                 -> blank line
  3. `input` / `sinput` / `extern` keyword               -> spaces
  4. dynamic arrays: `T name[]`, `T a[], b[]`, `T &name[]`, `const T &name[]`,
     `static T name[]`, `T *name[]`, `T name[][N]`        -> MqlArray<T> name
     (fixed-size arrays `T name[16]`, `T name[N][M]` and element accesses
     `name[i]` are left untouched)
  5. `(string)` casts                                    -> `(MqlStrCast)`
  6. D'2026.01.01 00:00' and C'r,g,b' literals            -> 0
  7. `#include <Trade\Trade.mqh>` / "..\x.mqh"           -> forward slashes;
     a file found next to the including file or under an MQL5 Include
     directory ($MQL5_INCLUDE, or <...>/MQL5/Include found above the source)
     is pre-processed too and the directive is pointed at that copy
  8. every string literal "..."                          -> string("...")
     so that `"a" + "b"` and `#define PREFIX "x"` + "y" work like in MQL5
  9. a `//` comment ending in a backslash gets a trailing space (C++ would
     splice the next line into the comment, MQL5 does not)

Whole-file pass (MQL5 lets a function be called before it is defined, C++
does not): forward declarations of every top-level struct/class/union/enum
and a prototype of every top-level function are generated from the file's
own text and inserted INLINE at the start of the first top-level definition
(no new line). Enum definitions get an explicit `:int` base (needed for the
opaque forward declaration) and default arguments move from the definition
into the prototype.

Usage: preprocess.py <source.mq5> <output.cpp>
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHIM_INCLUDE_DIR = os.path.join(HERE, "include")
VERBOSE = os.environ.get("MQLCHECK_VERBOSE", "") not in ("", "0")


# --------------------------------------------------------------------------- io
def read_text(path):
    data = open(path, "rb").read()
    if data.startswith(b"\xff\xfe") or data.startswith(b"\xfe\xff"):
        return data.decode("utf-16")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        return data.decode("cp1252", errors="replace")


def c_quote(path):
    return '"' + path.replace("\\", "\\\\").replace('"', '\\"') + '"'


# ------------------------------------------------------------------ lexical scan
def scan(line, in_block):
    """Lexically classify one line.

    Returns (code, nocomment, in_block_after, dc_spans, str_spans):
      code       same length as line; comments, string literals and character
                 literals replaced by spaces -> safe for regexes
      nocomment  same length as line; only comments replaced by spaces
      dc_spans   (start, end) of MQL5 D'...' / C'...' literals in code
      str_spans  (start, end) of "..." literals in code
    """
    n = len(line)
    code = list(line)
    noc = list(line)
    dc_spans = []
    str_spans = []
    i = 0
    while i < n:
        c = line[i]
        if in_block:
            j = line.find("*/", i)
            end = n if j < 0 else j + 2
            for k in range(i, end):
                code[k] = noc[k] = " "
            i = end
            if j >= 0:
                in_block = False
            continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            for k in range(i, n):
                code[k] = noc[k] = " "
            break
        if c == "/" and i + 1 < n and line[i + 1] == "*":
            code[i] = code[i + 1] = noc[i] = noc[i + 1] = " "
            i += 2
            in_block = True
            continue
        if c == '"' or c == "'":
            start = i
            is_dc = False
            if c == "'" and i >= 1 and line[i - 1] in "DC":
                before = line[i - 2] if i >= 2 else " "
                if not (before.isalnum() or before == "_"):
                    is_dc = True
                    start = i - 1
            j = i + 1
            while j < n and line[j] != c:
                if line[j] == "\\":
                    j += 1
                j += 1
            j = min(j + 1, n)
            for k in range(start, j):
                code[k] = " "
            if is_dc:
                dc_spans.append((start, j))
            elif c == '"':
                str_spans.append((start, j))
            i = j
            continue
        i += 1
    return "".join(code), "".join(noc), in_block, dc_spans, str_spans


def apply_edits(line, edits):
    """edits: list of (start, end, replacement) positions on the same line."""
    for start, end, rep in sorted(edits, key=lambda e: e[0], reverse=True):
        line = line[:start] + rep + line[end:]
    return line


# ------------------------------------------------------------- rewrite patterns
RE_BLANK_DIRECTIVE = re.compile(r"^\s*#\s*(property|import|resource)\b")
RE_INPUT_GROUP = re.compile(r"^\s*input\s+group\b")
RE_INPUT_KW = re.compile(r"\b(sinput|input|extern)\b(?=\s)")
RE_INCLUDE = re.compile(r'^(\s*#\s*include\s*)([<"])([^>"]*)([>"])(.*)$')
RE_STRING_CAST = re.compile(r"\(\s*string\s*\)")
# "Type name[]" / "Type &name[]" / "Type *name[]" / "Type name[][N]"; the
# separator between type and name must be real (whitespace, & or *) so the
# regex can never split an identifier.
RE_ARRAY_DECL = re.compile(
    r"\b(?P<type>(?:(?:unsigned|signed)\s+)?[A-Za-z_]\w*)"
    r"(?P<sep>\s*[*&]\s*|\s+)"
    r"(?P<name>[A-Za-z_]\w*)\s*\[\s*\]"
    r"(?P<dim2>\s*\[\s*(?P<n>[^\[\]]+?)\s*\])?"
)
# ", name[]" continuation declarators of the same statement
RE_ARRAY_CONT = re.compile(r",\s*(?P<amp>&)?\s*(?P<name>[A-Za-z_]\w*)\s*\[\s*\](?P<dim2>\s*\[\s*(?P<n>[^\[\]]+?)\s*\])?")
NOT_A_TYPE = {"return", "else", "case", "delete", "new", "goto", "sizeof", "typedef", "throw", "do", "const", "static", "input", "sinput"}


def array_replacement(m):
    typ = re.sub(r"\s+", " ", m.group("type"))
    sep = m.group("sep")
    ptr = "*" if "*" in sep else ""
    amp = "&" if "&" in sep else ""
    if m.group("dim2"):
        return "MqlArray2<%s%s, %s> %s%s" % (typ, ptr, m.group("n").strip(), amp, m.group("name"))
    return "MqlArray<%s%s> %s%s" % (typ, ptr, amp, m.group("name"))


def rewrite_arrays(line, code):
    edits = []
    last_end = -1
    for m in RE_ARRAY_DECL.finditer(code):
        if m.group("type") in NOT_A_TYPE:
            continue
        edits.append((m.start(), m.end(), array_replacement(m)))
        last_end = m.end()
    if last_end >= 0:
        # continuation declarators after the last declaration, up to end of statement
        stop = len(code)
        for ch in ";){":
            p = code.find(ch, last_end)
            if p >= 0:
                stop = min(stop, p)
        for m in RE_ARRAY_CONT.finditer(code, last_end, stop):
            amp = "&" if m.group("amp") else ""
            if m.group("dim2"):
                edits.append((m.start(), m.end(), ", %s%s" % (amp, m.group("name"))))
            else:
                edits.append((m.start(), m.end(), ", %s%s" % (amp, m.group("name"))))
    return apply_edits(line, edits) if edits else line


# --------------------------------------------------------------- include lookup
def mql5_include_dirs(src_path):
    dirs = []
    for d in os.environ.get("MQL5_INCLUDE", "").split(os.pathsep):
        if d and os.path.isdir(d):
            dirs.append(os.path.abspath(d))
    # walk up from the source looking for <...>/MQL5/Include
    d = os.path.dirname(os.path.abspath(src_path))
    while True:
        for cand in (os.path.join(d, "Include") if os.path.basename(d) == "MQL5" else None,
                     os.path.join(d, "MQL5", "Include")):
            if cand and os.path.isdir(cand) and cand not in dirs:
                dirs.append(cand)
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return dirs


def resolve_include(spec, quoted, including_dir, inc_dirs):
    """Absolute path of a user include to pre-process, or None when the shim
    provides the file (or nothing is found: g++ will then complain)."""
    rel = spec.replace("\\", "/").strip()
    if quoted:
        cand = os.path.normpath(os.path.join(including_dir, rel))
        if os.path.isfile(cand):
            return cand
    if os.path.isfile(os.path.join(SHIM_INCLUDE_DIR, rel)):
        return None
    for d in inc_dirs:
        cand = os.path.normpath(os.path.join(d, rel))
        if os.path.isfile(cand):
            return cand
    return None


# ------------------------------------------------------- forward declarations
RE_TYPE_HEAD = re.compile(r"^(?:template\s*<[^>]*>\s*)?(struct|class|union|enum|namespace)\b\s*(?:class\s+)?([A-Za-z_]\w*)?")
RE_TEMPLATE_PREFIX = re.compile(r"^template\s*<[^>]*>\s*")


class Hoister:
    """Scans the rewritten lines for top-level definitions and produces the
    inline forward-declaration blocks (see module docstring)."""

    def __init__(self, out, first):
        self.out = out
        self.codes = []
        self.nocs = []
        in_block = False
        for idx, line in enumerate(out):
            if idx < first:
                self.codes.append(" " * len(line))
                self.nocs.append(" " * len(line))
                continue
            code, noc, in_block, _, _ = scan(line, in_block)
            if code.lstrip().startswith("#"):
                code = " " * len(code)
                noc = " " * len(noc)
            self.codes.append(code)
            self.nocs.append(noc)
        self.types = []        # (kind, name)
        self.enum_marks = []   # (li, ci) where ":int" is inserted
        self.protos = []       # (name, text_with_defaults, text_without_defaults)
        self.declared = set()
        self.default_positions = []   # (li, ci) chars to blank in definitions
        self.first_type = None
        self.first_func = None

    def run(self):
        codes = self.codes
        depth = 0
        stmt = None          # dict: start, chars [(li, ci, code_ch, noc_ch)], paren, eq0
        in_init = False      # inside a brace initializer of a declaration
        for li in range(len(codes)):
            code = codes[li]
            for ci, ch in enumerate(code):
                if depth > 0 and not in_init:
                    if ch == "{":
                        depth += 1
                    elif ch == "}":
                        depth -= 1
                    continue
                if in_init:
                    stmt["chars"].append((li, ci, ch, self.nocs[li][ci]))
                    if ch == "{":
                        depth += 1
                    elif ch == "}":
                        depth -= 1
                        if depth == 0:
                            in_init = False
                    continue
                if stmt is None:
                    if ch.isspace():
                        continue
                    stmt = {"start": (li, ci), "chars": [], "paren": 0, "eq0": False}
                stmt["chars"].append((li, ci, ch, self.nocs[li][ci]))
                if ch == "(":
                    stmt["paren"] += 1
                elif ch == ")":
                    stmt["paren"] -= 1
                elif ch == "=" and stmt["paren"] == 0:
                    stmt["eq0"] = True
                elif ch == "{":
                    if stmt["eq0"]:
                        in_init = True
                        depth = 1
                        continue
                    self.definition(stmt)
                    depth = 1
                    stmt = None
                elif ch == ";" and stmt["paren"] == 0:
                    self.declaration(stmt)
                    stmt = None

    @staticmethod
    def text_of(chars, which):
        return "".join(c[which] for c in chars)

    def declaration(self, stmt):
        code = self.text_of(stmt["chars"], 2)
        if "(" in code and not stmt["eq0"]:
            m = re.search(r"([A-Za-z_]\w*)\s*\(", code)
            if m:
                self.declared.add(m.group(1))

    def definition(self, stmt):
        chars = stmt["chars"][:-1]           # drop the '{'
        code = self.text_of(chars, 2)
        noc = self.text_of(chars, 3)
        head = code.strip()
        m = RE_TYPE_HEAD.match(head)
        if m:
            kind, name = m.group(1), m.group(2)
            if self.first_type is None:
                self.first_type = stmt["start"]
            if kind == "namespace" or not name:
                return
            self.types.append((kind, name))
            if kind == "enum":
                off = code.index(head) + m.end(2)
                li, ci = chars[off - 1][0], chars[off - 1][1] + 1
                self.enum_marks.append((li, ci))
            return
        if "(" not in code:
            return
        before = code[:code.index("(")]
        before = RE_TEMPLATE_PREFIX.sub("", before.strip())
        if "::" in before or "operator" in before or len(before.split()) < 2:
            return
        name = before.split()[-1].lstrip("*&")
        if not re.match(r"^[A-Za-z_]\w*$", name):
            return
        if self.first_func is None:
            self.first_func = stmt["start"]
        if name in self.declared:
            return
        # default arguments: '=' at paren depth 1 up to the next ',' or ')' at depth 1
        paren = 0
        defaults = []       # list of (start_off, end_off)
        cur = None
        for off, (li, ci, ch, nch) in enumerate(chars):
            if ch == "(":
                paren += 1
            elif ch == ")":
                if paren == 1 and cur is not None:
                    defaults.append((cur, off))
                    cur = None
                paren -= 1
            elif ch == "," and paren == 1 and cur is not None:
                defaults.append((cur, off))
                cur = None
            elif ch == "=" and paren == 1 and cur is None:
                cur = off
        with_defaults = noc
        without = list(noc)
        for s, e in defaults:
            for k in range(s, e):
                without[k] = " "
                self.default_positions.append((chars[k][0], chars[k][1]))
        norm = lambda t: re.sub(r"\s+", " ", t).strip()
        self.protos.append((name, norm(with_defaults) + ";", norm("".join(without)) + ";", bool(defaults)))

    def apply(self):
        """Blank defaults in definitions, add ':int' to enums, insert blocks."""
        out = self.out
        for li, ci in self.default_positions:
            out[li] = out[li][:ci] + " " + out[li][ci + 1:]
        inserts = []
        for li, ci in self.enum_marks:
            inserts.append((li, ci, ":int"))
        p0 = min(p for p in (self.first_type, self.first_func) if p is not None) if (self.first_type or self.first_func) else None
        if p0 is not None:
            block = []
            for kind, name in self.types:
                block.append("%s %s%s;" % (kind, name, ":int" if kind == "enum" else ""))
            for name, with_d, without_d, has_d in self.protos:
                block.append(without_d)
            if block:
                inserts.append((p0[0], p0[1], " ".join(block) + " "))
        if self.first_func is not None:
            block = [with_d for name, with_d, without_d, has_d in self.protos if has_d]
            if block:
                inserts.append((self.first_func[0], self.first_func[1], " ".join(block) + " "))
        for li, ci, text in sorted(inserts, key=lambda t: (t[0], t[1]), reverse=True):
            out[li] = out[li][:ci] + text + out[li][ci:]


# ------------------------------------------------------------------- main pass
class Preprocessor:
    def __init__(self, out_dir):
        self.out_dir = out_dir
        self.inc_out_dir = os.path.join(out_dir, "inc")
        self.done = {}      # abs source path -> output path

    def process(self, src, out_path, is_main, inc_dirs):
        src_abs = os.path.abspath(src)
        if src_abs in self.done:
            return self.done[src_abs]
        self.done[src_abs] = out_path
        lines = read_text(src).split("\n")
        out = []
        if not is_main:
            out.append("#pragma once")          # MQL5 includes every file once
        out.append("#line 1 %s" % c_quote(src))
        first = len(out)
        in_block = False
        including_dir = os.path.dirname(src_abs)
        for raw in lines:
            line, in_block = self.rewrite_line(raw.rstrip("\r"), in_block, including_dir, inc_dirs)
            out.append(line)
        h = Hoister(out, first)
        h.run()
        h.apply()
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        with open(out_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(out))
            if not out[-1].endswith("\n"):
                f.write("\n")
        return out_path

    def rewrite_line(self, line, in_block, including_dir, inc_dirs):
        code, _, in_block_after, dc_spans, _ = scan(line, in_block)
        code_at_start = not in_block
        blank = "/*" if in_block_after else ""     # keep an opened block comment open

        # 6. D'...' / C'...' literals -> 0
        if dc_spans:
            line = apply_edits(line, [(s, e, "0") for s, e in dc_spans])
            code = scan(line, in_block)[0]

        # 1. directives that C++ does not know -> blank
        if code_at_start and RE_BLANK_DIRECTIVE.match(code):
            return blank, in_block_after
        # 7. #include: slashes, and user includes pre-processed in place
        m = RE_INCLUDE.match(line) if code_at_start else None
        if m and code[m.group(1).index("#")] == "#":
            head, open_q, spec, close_q, rest = m.groups()
            spec_fwd = spec.replace("\\", "/")
            target = resolve_include(spec_fwd, open_q == '"', including_dir, inc_dirs)
            if target is None:
                return "%s%s%s%s%s" % (head, open_q, spec_fwd, close_q, rest), in_block_after
            digest = hashlib.md5(target.encode("utf-8")).hexdigest()[:10]
            out_path = os.path.join(self.inc_out_dir, digest + "_" + os.path.basename(target))
            if VERBOSE:
                sys.stderr.write("mqlcheck: include %s -> %s\n" % (target, out_path))
            self.process(target, out_path, False, inc_dirs)
            return "%s%s%s" % (head, c_quote(out_path), rest), in_block_after
        # 2. input group -> blank
        if code_at_start and RE_INPUT_GROUP.match(code):
            return blank, in_block_after
        # 3. input / sinput / extern keyword -> spaces (keeps columns)
        edits = [(m.start(), m.end(), " " * (m.end() - m.start())) for m in RE_INPUT_KW.finditer(code)]
        if edits:
            line = apply_edits(line, edits)
            code = scan(line, in_block)[0]
        # 4. dynamic array declarations
        if "[" in code:
            new_line = rewrite_arrays(line, code)
            if new_line != line:
                line = new_line
                code = scan(line, in_block)[0]
        # 5. (string) casts
        edits = [(m.start(), m.end(), "(MqlStrCast)") for m in RE_STRING_CAST.finditer(code)]
        if edits:
            line = apply_edits(line, edits)
        # 8. string literals -> string("...")
        code, _, _, _, str_spans = scan(line, in_block)
        if str_spans:
            line = apply_edits(line, [(s, e, "string(" + line[s:e] + ")") for s, e in str_spans])
            code = scan(line, in_block)[0]
        # 9. backslash at the end of a comment
        if line.endswith("\\") and code and code[-1] == " ":
            line += " "
        return line, in_block_after


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: preprocess.py <source.mq5> <output.cpp>\n")
        return 2
    src, out_path = argv[1], argv[2]
    if not os.path.isfile(src):
        sys.stderr.write("mqlcheck: no such file: %s\n" % src)
        return 1
    pp = Preprocessor(os.path.dirname(os.path.abspath(out_path)))
    pp.process(src, out_path, True, mql5_include_dirs(src))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
