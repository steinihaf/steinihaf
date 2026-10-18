#!/usr/bin/env python3
"""mqlcheck pre-processor: turns an MQL5 source file into a C++ translation
unit that g++ can syntax-check against the mql5_shim.h fake runtime.

Guarantees: the output has exactly the same number of lines as the input
(nothing is inserted or deleted, only blanked or rewritten in place), and a
"#line 1 <original>" directive is prepended so g++ reports the original file
name and line numbers.

Usage: preprocess.py --shim DIR --work DIR [-I DIR]... [-v] FILE.mq5
Prints two lines on stdout: the generated .cpp path and the generated
forward-declaration header (to be passed to g++ with -include).
"""
import argparse
import os
import re
import sys

KEYWORDS = {
    "if", "for", "while", "switch", "return", "sizeof", "catch", "else", "new", "delete",
    "case", "throw", "goto", "typedef", "using", "namespace", "operator", "struct", "class",
    "enum", "union", "template", "typename", "do", "break", "continue", "default", "true",
    "false", "NULL", "const", "static", "virtual", "inline", "void", "int", "uint", "long",
    "ulong", "short", "ushort", "char", "uchar", "bool", "double", "float", "string",
    "datetime", "color", "unsigned", "signed", "auto", "this", "public", "private",
    "protected", "extern", "input", "sinput", "override", "final", "MqlArray", "MqlArray2",
}
NOT_A_TYPE = {"return", "delete", "case", "goto", "else", "new", "throw", "typedef", "struct",
              "class", "enum", "template", "operator", "do", "break", "continue", "default",
              "using", "namespace", "if", "for", "while", "switch", "sizeof", "union"}

VERBOSE = False


def note(msg):
    sys.stderr.write("mqlcheck: " + msg + "\n")


def vnote(msg):
    if VERBOSE:
        note(msg)


# ----------------------------------------------------------------- tokenizer
def tokenize(text):
    """Return (masked, nocomment, char_spans).
    masked   : comments and string/char literals replaced by spaces
    nocomment: only comments replaced by spaces
    char_spans: [(start, end)] of '...' literals (for D'..' / C'..' handling)
    All three keep the exact length and newlines of `text`."""
    n = len(text)
    masked = list(text)
    nocomment = list(text)
    spans = []
    i = 0
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            j = i
            while j < n and text[j] != "\n":
                masked[j] = " "
                nocomment[j] = " "
                j += 1
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = i + 2
            while j < n and not (text[j] == "*" and j + 1 < n and text[j + 1] == "/"):
                j += 1
            j = min(n, j + 2)
            for k in range(i, j):
                if text[k] != "\n":
                    masked[k] = " "
                    nocomment[k] = " "
            i = j
        elif c == '"' or c == "'":
            q = c
            j = i + 1
            while j < n and text[j] != q and text[j] != "\n":
                if text[j] == "\\":
                    j += 1
                j += 1
            j = min(n, j + 1)
            for k in range(i, j):
                if text[k] != "\n":
                    masked[k] = " "
            if q == "'":
                spans.append((i, j))
            i = j
        else:
            i += 1
    return "".join(masked), "".join(nocomment), spans


def apply_edits(text, edits):
    """edits: list of (start, end, replacement); applied right-to-left."""
    for s, e, r in sorted(edits, key=lambda t: t[0], reverse=True):
        text = text[:s] + r + text[e:]
    return text


def keep_newlines(span_text, replacement):
    """Make `replacement` occupy as many lines as `span_text` did."""
    return replacement + "\n" * span_text.count("\n")


def blank_keep_newlines(s):
    return "".join("\n" if ch == "\n" else " " for ch in s)


# ----------------------------------------------------------------- passes
def pass_datetime_color_literals(text):
    _, _, spans = tokenize(text)
    edits = []
    for s, e in spans:
        if s >= 1 and text[s - 1] in "DC" and (s < 2 or not (text[s - 2].isalnum() or text[s - 2] == "_")):
            edits.append((s - 1, e, keep_newlines(text[s - 1:e], "0")))
    return apply_edits(text, edits)


STRING_CAST_RE = re.compile(r"\(\s*string\s*\)")


def pass_string_cast(text):
    masked, _, _ = tokenize(text)
    edits = [(m.start(), m.end(), "(MqlStrCast)") for m in STRING_CAST_RE.finditer(masked)]
    return apply_edits(text, edits)


PARAM_ARR_RE = re.compile(
    r"\b(const\s+)?([A-Za-z_]\w*)\s*(?<!&)&(?!&)\s*([A-Za-z_]\w*)\s*\[\s*\]((?:\s*\[[^\]]*\])*)")


def pass_array_params(text):
    masked, _, _ = tokenize(text)
    edits = []
    for m in PARAM_ARR_RE.finditer(masked):
        const, typ, name, extra = m.group(1) or "", m.group(2), m.group(3), m.group(4)
        if typ in NOT_A_TYPE:
            continue
        dims = re.findall(r"\[([^\]]*)\]", extra)
        if len(dims) == 1 and dims[0].strip():
            new = "%sMqlArray2<%s,%s>& %s" % (const, typ, dims[0].strip(), name)
        else:
            new = "%sMqlArray<%s>& %s" % (const, typ, name)
        edits.append((m.start(), m.end(), keep_newlines(masked[m.start():m.end()], new)))
    return apply_edits(text, edits)


DECL_RE = re.compile(r"^(\s*)((?:(?:static|const|input|sinput|extern)\s+)*)([A-Za-z_]\w*)\s+(\S.*?)\s*$", re.S)
DECLARATOR_RE = re.compile(r"^([A-Za-z_]\w*)\s*((?:\[[^\]]*\]\s*)*)(=\s*.+)?$", re.S)


def split_top(s, sep=","):
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == sep and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    out.append("".join(cur))
    return out


def pass_array_decls(text):
    masked, nocomment, _ = tokenize(text)
    edits = []
    start = 0
    for i, ch in enumerate(masked + ";"):
        if ch not in ";{}":
            continue
        seg = masked[start:i]
        if "[]" in seg.replace(" ", "") or re.search(r"\[\s*\]", seg):
            edit = rewrite_decl(seg, nocomment[start:i], start)
            if edit:
                edits.append(edit)
        start = i + 1
    return apply_edits(text, edits)


def rewrite_decl(seg, seg_src, offset):
    m = DECL_RE.match(seg)
    if not m:
        return None
    lead, qual, typ, decls = m.group(1), m.group(2), m.group(3), m.group(4)
    if typ in NOT_A_TYPE or typ in ("return",):
        return None
    if seg.lstrip().startswith("#"):
        return None
    # take declarators from the comment-free source so initializers keep strings
    decl_start = m.start(4)
    decls_src = seg_src[decl_start:m.end(4)]
    parsed = []
    for d in split_top(decls_src):
        dm = DECLARATOR_RE.match(d.strip())
        if not dm:
            return None
        name, dims_txt, init = dm.group(1), dm.group(2), dm.group(3) or ""
        dims = [x.strip() for x in re.findall(r"\[([^\]]*)\]", dims_txt)]
        init = " ".join(init.split())
        if dims and dims[0] == "":
            if len(dims) == 2 and dims[1]:
                kind = "MqlArray2<%s,%s>" % (typ, dims[1])
            else:
                kind = "MqlArray<%s>" % typ
            parsed.append((kind, name + (" " + init if init else "")))
        else:
            tail = "".join("[%s]" % x for x in dims)
            parsed.append((typ, name + tail + (" " + init if init else "")))
    if not any(k.startswith("MqlArray") for k, _ in parsed):
        return None
    groups = []
    for kind, decl in parsed:
        if groups and groups[-1][0] == kind:
            groups[-1][1].append(decl)
        else:
            groups.append((kind, [decl]))
    qual = " ".join(w for w in qual.split() if w not in ("input", "sinput", "extern"))
    qual = qual + " " if qual else ""
    body = "; ".join("%s%s %s" % (qual, kind, ", ".join(ds)) for kind, ds in groups)
    new = lead + body
    span_text = seg
    return (offset, offset + len(seg), keep_newlines(span_text[len(lead):], new))


ENUM_RE = re.compile(r"\benum\s+([A-Za-z_]\w*)(\s*)\{")


def pass_enum_underlying(text):
    masked, _, _ = tokenize(text)
    edits = []
    for m in ENUM_RE.finditer(masked):
        edits.append((m.end(1), m.end(1), " : int"))
    return apply_edits(text, edits)


# ----------------------------------------------------------------- functions
FUNC_RE = re.compile(
    r"((?:(?:static|virtual|inline|const)\s+)*)([A-Za-z_]\w*)(\s*[*&])?\s+([A-Za-z_]\w*)\s*\(")


def brace_depth_map(masked):
    depth = [0] * (len(masked) + 1)
    d = 0
    for i, ch in enumerate(masked):
        depth[i] = d
        if ch == "{":
            d += 1
        elif ch == "}":
            d -= 1
    depth[len(masked)] = d
    return depth


def match_paren(masked, i):
    d = 0
    for j in range(i, len(masked)):
        if masked[j] == "(":
            d += 1
        elif masked[j] == ")":
            d -= 1
            if d == 0:
                return j
    return -1


def line_of(text, pos):
    s = text.rfind("\n", 0, pos) + 1
    e = text.find("\n", pos)
    return text[s:e if e >= 0 else len(text)]


def boundary_ok(masked, pos):
    j = pos - 1
    while j >= 0 and masked[j].isspace():
        j -= 1
    if j < 0:
        return True
    if masked[j] in ";{}":
        return True
    if line_of(masked, j).lstrip().startswith("#"):
        return True
    return False


def scan_functions(text, shim_ids):
    """Return (edits_to_blank_defaults, prototypes, user_prototype_names)."""
    masked, nocomment, _ = tokenize(text)
    depth = brace_depth_map(masked)
    protos = []
    user_proto_names = set()
    defs = []
    for m in FUNC_RE.finditer(masked):
        if depth[m.start()] != 0:
            continue
        qual, ret, ptr, name = m.group(1), m.group(2), (m.group(3) or "").strip(), m.group(4)
        if name in KEYWORDS or ret in NOT_A_TYPE or ret in ("if", "while", "for", "switch"):
            continue
        if not boundary_ok(masked, m.start()):
            continue
        if line_of(masked, m.start()).lstrip().startswith("#"):
            continue
        prev = masked[max(0, m.start() - 2):m.start()]
        if ":" in prev or ">" in prev:
            continue
        lp = m.end() - 1
        rp = match_paren(masked, lp)
        if rp < 0:
            continue
        j = rp + 1
        while j < len(masked) and masked[j].isspace():
            j += 1
        if masked.startswith("const", j):
            j += 5
            while j < len(masked) and masked[j].isspace():
                j += 1
        if j >= len(masked):
            continue
        if masked[j] == ";":
            user_proto_names.add(name)
            if "=" in masked[lp:rp]:
                user_proto_names.add(name + "=")
            continue
        if masked[j] != "{":
            continue
        defs.append((qual, ret, ptr, name, lp, rp))

    edits = []
    for qual, ret, ptr, name, lp, rp in defs:
        params_src = nocomment[lp + 1:rp]
        params_masked = masked[lp + 1:rp]
        if name in user_proto_names and (name + "=") not in user_proto_names:
            continue  # user wrote a prototype without defaults: nothing to do
        pieces = split_top(params_src)
        pieces_m = split_top(params_masked)
        if len(pieces) != len(pieces_m):
            continue
        all_safe = True
        proto_params = []
        default_spans = []
        pos = lp + 1
        type_ids = set()
        for p, pm in zip(pieces, pieces_m):
            eq = top_level_eq(pm)
            if eq >= 0:
                default_m = pm[eq + 1:]
                ids = set(re.findall(r"\b[A-Za-z_]\w*\b", default_m))
                if not ids <= shim_ids | KEYWORDS:
                    all_safe = False
                default_spans.append((pos + eq, pos + len(p)))
                head = p[:eq]
            else:
                head = p
            head_ids = re.findall(r"\b[A-Za-z_]\w*\b", head)
            if len(head_ids) >= 2:
                type_ids.update(head_ids[:-1])
            elif head_ids:
                type_ids.update(head_ids)
            proto_params.append((head, p[eq:] if eq >= 0 else ""))
            pos += len(p) + 1
        type_ids.update(re.findall(r"\b[A-Za-z_]\w*\b", ret))
        type_ids -= KEYWORDS
        type_ids -= shim_ids
        if name in user_proto_names:
            # user prototype carries defaults; definition must not repeat them
            for s, e in default_spans:
                edits.append((s, e, blank_keep_newlines(text[s:e])))
            continue
        if all_safe:
            params_txt = ", ".join(" ".join((h + " " + d).split()) for h, d in proto_params)
            for s, e in default_spans:
                edits.append((s, e, blank_keep_newlines(text[s:e])))
        else:
            params_txt = ", ".join(" ".join(h.split()) for h, _ in proto_params)
        proto = "%s%s%s %s(%s);" % (qual, ret, ptr, name, params_txt)
        protos.append((proto, type_ids))
    return edits, protos


def top_level_eq(s):
    d = 0
    for i, ch in enumerate(s):
        if ch in "([{<":
            d += 1
        elif ch in ")]}>":
            d -= 1
        elif ch == "=" and d == 0 and (i == 0 or s[i - 1] not in "=!<>") and (i + 1 >= len(s) or s[i + 1] != "="):
            return i
    return -1


TYPE_DEF_RE = re.compile(r"\b(struct|class|enum|union)\s+([A-Za-z_]\w*)\s*(?::[^{;]*)?\{")


def collect_user_types(masked, table):
    for m in TYPE_DEF_RE.finditer(masked):
        table.setdefault(m.group(2), m.group(1))


# ----------------------------------------------------------------- includes
INCLUDE_RE = re.compile(r'^(\s*)#\s*include\s*([<"])([^>"]+)[>"](.*)$')


class Processor:
    def __init__(self, shim_dir, work_dir, user_roots):
        self.shim_dir = os.path.abspath(shim_dir)
        self.work_dir = os.path.abspath(work_dir)
        self.user_roots = user_roots
        self.seen = {}
        self.protos = []        # (proto, type_ids)
        self.user_types = {}    # name -> struct/class/enum
        self.counter = 0
        self.shim_ids = self.load_shim_ids()

    def load_shim_ids(self):
        ids = set()
        for root, _, files in os.walk(self.shim_dir):
            for f in files:
                try:
                    with open(os.path.join(root, f), "r", encoding="utf-8", errors="replace") as fh:
                        ids.update(re.findall(r"\b[A-Za-z_]\w*\b", fh.read()))
                except OSError:
                    pass
        return ids

    def read(self, path):
        with open(path, "rb") as fh:
            raw = fh.read()
        if raw.startswith(b"\xff\xfe") or raw.startswith(b"\xfe\xff"):
            text = raw.decode("utf-16", errors="replace")
        else:
            text = raw.decode("utf-8-sig", errors="replace")
        return text.replace("\r\n", "\n").replace("\r", "\n")

    def roots_for(self, path):
        roots = [os.path.dirname(os.path.abspath(path))]
        d = roots[0]
        while True:
            if os.path.basename(d) == "Include":
                roots.append(d)
            if os.path.isdir(os.path.join(d, "Include")):
                roots.append(os.path.join(d, "Include"))
            nd = os.path.dirname(d)
            if nd == d:
                break
            d = nd
        roots += self.user_roots
        for extra in (os.path.join(os.getcwd(), "Include"), os.path.join(os.getcwd(), "MQL5", "Include")):
            if os.path.isdir(extra):
                roots.append(extra)
        return roots

    def resolve_include(self, inc, from_path):
        inc = inc.replace("\\", "/").strip()
        if os.path.isfile(os.path.join(self.shim_dir, inc)):
            return ("shim", inc)
        for root in self.roots_for(from_path):
            cand = os.path.normpath(os.path.join(root, inc))
            if os.path.isfile(cand):
                return ("user", cand)
        return ("missing", inc)

    def process(self, path, is_main):
        real = os.path.realpath(path)
        if real in self.seen:
            return None
        self.counter += 1
        base = os.path.basename(path)
        if is_main:
            out = os.path.join(self.work_dir, os.path.splitext(base)[0] + ".cpp")
        else:
            out = os.path.join(self.work_dir, "inc", "%d_%s" % (self.counter, base))
        self.seen[real] = out
        text = self.read(path)

        # --- line-level passes
        lines = text.split("\n")
        for i, ln in enumerate(lines):
            st = ln.lstrip()
            if re.match(r"#\s*(property|import|resource)\b", st):
                lines[i] = ""
            elif re.match(r"(input|sinput)\s+group\b", st):
                lines[i] = ""
            else:
                mi = INCLUDE_RE.match(ln)
                if mi:
                    kind, target = self.resolve_include(mi.group(3), path)
                    if kind == "shim":
                        lines[i] = "%s#include <%s>" % (mi.group(1), target)
                    elif kind == "user":
                        sub = self.process(target, False)
                        lines[i] = ("%s#include \"%s\"" % (mi.group(1), sub)) if sub else ""
                    else:
                        note("%s: include <%s> not found - line blanked; errors about its symbols may follow "
                             "(pass -I <MQL5/Include dir>)" % (path, target))
                        lines[i] = ""
                else:
                    lines[i] = re.sub(r"^(\s*)(input|sinput|extern)\s+", r"\1", ln)
        text = "\n".join(lines)

        # --- token-aware passes (each keeps the line count)
        text = pass_datetime_color_literals(text)
        text = pass_string_cast(text)
        text = pass_array_params(text)
        text = pass_array_decls(text)
        text = pass_enum_underlying(text)

        masked, _, _ = tokenize(text)
        collect_user_types(masked, self.user_types)
        edits, protos = scan_functions(text, self.shim_ids)
        text = apply_edits(text, edits)
        self.protos.extend(protos)

        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8") as fh:
            fh.write('#line 1 "%s"\n' % path.replace("\\", "\\\\").replace('"', '\\"'))
            fh.write(text)
        vnote("%s -> %s" % (path, out))
        return out

    def write_fwd(self, out):
        fwd_types = []
        lines = []
        for proto, type_ids in self.protos:
            ok = True
            for t in sorted(type_ids):
                kind = self.user_types.get(t)
                if kind is None:
                    ok = False
                    vnote("no forward declaration for %s (type %s unknown)" % (proto, t))
                    break
                decl = ("enum %s : int;" % t) if kind == "enum" else ("%s %s;" % (kind, t))
                if decl not in fwd_types:
                    fwd_types.append(decl)
            if ok:
                lines.append(proto)
        with open(out, "w", encoding="utf-8") as fh:
            fh.write("// generated by mqlcheck: forward declarations so MQL5's\n")
            fh.write("// define-after-use style compiles as C++\n#pragma once\n")
            for d in fwd_types:
                fh.write(d + "\n")
            for p in lines:
                fh.write(p + "\n")


def main():
    global VERBOSE
    ap = argparse.ArgumentParser()
    ap.add_argument("--shim", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("-I", dest="inc", action="append", default=[])
    ap.add_argument("-v", dest="verbose", action="store_true")
    ap.add_argument("file")
    a = ap.parse_args()
    VERBOSE = a.verbose
    roots = list(a.inc)
    env = os.environ.get("MQL_INCLUDE", "")
    roots += [p for p in env.split(os.pathsep) if p]
    proc = Processor(a.shim, a.work, roots)
    cpp = proc.process(a.file, True)
    fwd = os.path.join(proc.work_dir, os.path.splitext(os.path.basename(a.file))[0] + ".fwd.h")
    proc.write_fwd(fwd)
    print(cpp)
    print(fwd)


if __name__ == "__main__":
    main()
