#!/usr/bin/env python3
"""Generate MT5 .set preset files from the inputs declared in the Expert Advisors.

Usage: python3 tools/gen_presets.py
Each preset = the EA's defaults + the overrides listed in EAS below.
"""
import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXPERTS = ROOT / 'MQL5/Experts'
OUT = ROOT / 'MQL5/Presets'

# well-known MQL5 enum / constant values used by the inputs
KNOWN = {
    'PERIOD_CURRENT': 0, 'PERIOD_M1': 1, 'PERIOD_M5': 5, 'PERIOD_M15': 15, 'PERIOD_M30': 30,
    'PERIOD_H1': 16385, 'PERIOD_H4': 16388, 'PERIOD_D1': 16408, 'PERIOD_W1': 32769, 'PERIOD_MN1': 49153,
    'MODE_SMA': 0, 'MODE_EMA': 1, 'MODE_SMMA': 2, 'MODE_LWMA': 3,
    'clrRed': 255, 'clrYellow': 65535, 'clrWhite': 16777215, 'clrAqua': 16776960,
}

# SessionSweepEA: lines shared by the three presets
SWEEP_NOTES = [
    'Signal timeframe is fixed to M15 (InpSignalTF), so the chart timeframe does not matter.',
    'Session times are broker server time for a GMT+2 / GMT+3 server (New York time + 7 hours):',
    'compare with the clock in Market Watch and adjust InpAsia / InpLondon / InpNY Start and End.',
    'The file is not tied to the symbol name; load it on your broker\'s chart of this instrument.',
    'Backtests of these values showed no proven edge. Run it on a demo account first.',
]

# EA source file -> {'newline': line ending of its presets, 'presets': {file name: comment + overrides}}
EAS = {
    'LineTouchEA.mq5': {
        'newline': '\n',
        'presets': {
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
        },
    },
    'SessionSweepEA.mq5': {
        'newline': '\r\n',              # as MetaTrader writes its own .set files
        'presets': {
            'SessionSweepEA_XAUUSD_M15.set': {
                'comment': ['SessionSweepEA preset - XAUUSD (gold)',
                            'Buffers are the EA defaults, as fractions of the daily ATR:',
                            'break 0.01, re-entry 0, stop buffer 0.03, minimum stop 0.06.'] + SWEEP_NOTES,
                'overrides': {'InpSignalTF': 'PERIOD_M15'},
            },
            'SessionSweepEA_EURUSD_M15.set': {
                'comment': ['SessionSweepEA preset - EURUSD',
                            'Buffers as fractions of the daily ATR: break 0.01, re-entry 0, stop buffer 0.03,',
                            'minimum stop 0.25 (EA default 0.06, which leaves the stop only a few spreads wide).'] + SWEEP_NOTES,
                'overrides': {'InpSignalTF': 'PERIOD_M15', 'InpMinSLATR': '0.25'},
            },
            'SessionSweepEA_GBPUSD_M15.set': {
                'comment': ['SessionSweepEA preset - GBPUSD',
                            'Buffers as fractions of the daily ATR: break 0.01, re-entry 0, stop buffer 0.03,',
                            'minimum stop 0.25 (EA default 0.06, which leaves the stop only a few spreads wide).'] + SWEEP_NOTES,
                'overrides': {'InpSignalTF': 'PERIOD_M15', 'InpMinSLATR': '0.25'},
            },
        },
    },
}


def parse_ea(path):
    """Return (user enums {name: {member: value}}, inputs [(type, name, default)]) of an EA."""
    src = path.read_text(encoding='utf-8')
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
    return enums, inputs


def encode(enums, typ, name, default):
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
for ea, cfg in EAS.items():
    enums, inputs = parse_ea(EXPERTS / ea)
    names = {name for _, name, _ in inputs}
    for fname, spec in cfg['presets'].items():
        unknown = set(spec['overrides']) - names
        if unknown:
            raise SystemExit(f'{fname}: {ea} has no input {sorted(unknown)}')
        lines = ['; ' + c for c in spec['comment']]
        for typ, name, default in inputs:
            value = spec['overrides'].get(name, default)
            lines.append(encode(enums, typ, name, value))
        nl = cfg['newline']
        (OUT / fname).write_bytes((nl.join(lines) + nl).encode('ascii'))
        print(f'{fname}: {len(inputs)} inputs')
