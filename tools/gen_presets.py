#!/usr/bin/env python3
"""Generate MT5 .set preset files from the inputs declared in LineTouchEA.mq5.

Usage: python3 tools/gen_presets.py
Each preset = the EA defaults + the overrides listed in PRESETS below.
"""
import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
EA = ROOT / 'MQL5/Experts/LineTouchEA.mq5'
OUT = ROOT / 'MQL5/Presets'

# well-known MQL5 enum / constant values used by the inputs
KNOWN = {
    'PERIOD_CURRENT': 0, 'PERIOD_M1': 1, 'PERIOD_M5': 5, 'PERIOD_M15': 15, 'PERIOD_M30': 30,
    'PERIOD_H1': 16385, 'PERIOD_H4': 16388, 'PERIOD_D1': 16408, 'PERIOD_W1': 32769, 'PERIOD_MN1': 49153,
    'MODE_SMA': 0, 'MODE_EMA': 1, 'MODE_SMMA': 2, 'MODE_LWMA': 3,
    'clrRed': 255, 'clrYellow': 65535, 'clrWhite': 16777215, 'clrAqua': 16776960,
}

PRESETS = {
    'LineTouchEA_XAUUSD_H1_chart_lines.set': {
        'comment': ['LineTouchEA preset - trade the lines already on the chart (XAUUSD H1)',
                    'Sources: chart lines (U_MTF_SRTrend SR_n / Trend_* lines, hand-drawn lines) + ValueAreaLevels buffers.',
                    'The built-in ZigZag engine is off because the chart already shows those lines.'],
        'overrides': {'InpVAL_Enable': 'true'},
    },
    'LineTouchEA_XAUUSD_H1_builtin.set': {
        'comment': ['LineTouchEA preset - self-contained levels for backtesting (XAUUSD H1)',
                    'Sources: ValueAreaLevels buffers + built-in MTF ZigZag S/R and trend lines.',
                    'Chart objects are off: they do not exist in a non-visual Strategy Tester run.'],
        'overrides': {'InpObjUseHLines': 'false', 'InpObjUseTrendLines': 'false',
                      'InpVAL_Enable': 'true', 'InpSR_Enable': 'true'},
    },
}

src = EA.read_text(encoding='utf-8')

# user enums declared in the EA: name -> {member: value}
enums = {}
for m in re.finditer(r'enum\s+(\w+)\s*\{(.*?)\};', src, re.S):
    name, body = m.group(1), m.group(2)
    members, val = {}, 0
    for line in body.splitlines():
        line = line.split('//')[0].strip().rstrip(',')
        if not line:
            continue
        if '=' in line:
            k, v = [x.strip() for x in line.split('=')]
            val = int(v)
        else:
            k = line
        members[k] = val
        val += 1
    enums[name] = members

inputs = re.findall(r'^input\s+(\w+)\s+(Inp\w+)\s*=\s*([^;]+);', src, re.M)

def encode(typ, name, default):
    d = default.strip()
    if typ == 'string':
        return f'{name}={d.strip(chr(34))}'
    if typ == 'bool':
        return f'{name}={d}||false||0||true||N'
    if typ in ('int', 'uint', 'long', 'ulong'):
        v = int(d)
        return f'{name}={v}||{v}||1||{max(v * 2, v + 10)}||N'
    if typ == 'double':
        v = float(d)
        return f'{name}={v}||{v}||{max(v / 10, 0.1):g}||{max(v * 2, 1.0):g}||N'
    if typ == 'color':
        v = KNOWN[d]
        return f'{name}={v}||{v}||0||{v}||N'
    if typ in enums:
        v = enums[typ][d]
        return f'{name}={v}||{v}||0||{max(enums[typ].values())}||N'
    if d in KNOWN:
        v = KNOWN[d]
        return f'{name}={v}||{v}||0||{v}||N'
    raise SystemExit(f'cannot encode {typ} {name} = {d}')

OUT.mkdir(parents=True, exist_ok=True)
for fname, spec in PRESETS.items():
    lines = ['; ' + c for c in spec['comment']]
    for typ, name, default in inputs:
        value = spec['overrides'].get(name, default)
        lines.append(encode(typ, name, value))
    (OUT / fname).write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'{fname}: {len(inputs)} inputs')
