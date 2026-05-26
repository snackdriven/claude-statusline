#!/usr/bin/env python3
"""assemble.py — zoned + adaptive statusline row assembler.

Reads a JSON array of region objects on stdin, prints the composed statusline
(one line per row). Width-independent: groups regions into zones (◆-separated),
shortens lowest-priority regions to their `short` variant when a row won't fit,
then drops trailing zones — never positions against the terminal edge, so it
never floats or wraps.

Region object (all but text optional):
  { text, short?, color?, group?, priority?, row?, ttl_sec?, updated_at? }

Dependency-free on purpose (no wcwidth) so it runs under the statusline's
exec env. Width heuristic matches render.sh: strip ANSI, count code points,
+1 for each astral-plane char (4-byte UTF-8 emoji ≈ 2 display cols).

Usage: assemble.py <budget> <now_epoch>   (regions JSON on stdin)
"""
import sys, json, re

ANSI = re.compile('\x1b\\[[0-9;]*m')
RESET = '\033[0m'
ZONE_DIV = '   ◆   '
INTRA = ' · '
COLORS = {
    'dim': '\033[90m', 'cyan': '\033[36m', 'magenta': '\033[35m',
    'yellow': '\033[33m', 'red': '\033[31m', 'green': '\033[32m',
    'default': '\033[0m',
}

# Layout lives here (presentation concern), not scattered across producers.
# id -> (row, group). Regions not listed keep their own row + group=id.
# Row 0 reads: work ◆ ctx ◆ cal.  Row 1: ambient.
LAYOUT = {
    'ticket':   (0, 'work'), 'incoming': (0, 'work'),
    'project':  (0, 'ctx'),  'gh':       (0, 'ctx'),
    'coord':    (0, 'work'),  # transient + high-pri; in ctx it distorts zone-drop order
    'meeting':  (0, 'cal'),
    'buddy':    (1, 'amb'),  'spotify':  (1, 'amb'),
}
# Fixed left-to-right zone order (semantic, stable) — NOT priority-derived,
# so zones don't reshuffle as counts change. Lower rank = further left.
ZONE_RANK = {'work': 0, 'ctx': 1, 'cal': 2, 'amb': 0}

def vwidth(s):
    v = ANSI.sub('', s)
    return sum(2 if ord(c) > 0xFFFF else 1 for c in v)

def wrap(text, color):
    return COLORS.get(color, COLORS['default']) + text + RESET

def main():
    budget = int(sys.argv[1]) if len(sys.argv) > 1 else 116
    now = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    try:
        regions = json.load(sys.stdin)
    except Exception:
        return
    if not isinstance(regions, list):
        return

    live = []
    for r in regions:
        if not isinstance(r, dict):
            continue
        text = r.get('text')
        if not text:
            continue
        if now and (now - r.get('updated_at', 0)) > r.get('ttl_sec', 60):
            continue
        rid = r.get('id')
        row = r.get('row', 0)
        group = r.get('group') or rid or 'z'
        if rid in LAYOUT:
            row, group = LAYOUT[rid]
        live.append({
            'text': text,
            'short': r.get('short') or text,
            'color': r.get('color', 'default'),
            'group': group,
            'pri': r.get('priority', 0),
            'row': row,
        })
    if not live:
        return

    out_lines = []
    for row in sorted({r['row'] for r in live}):
        items = [r for r in live if r['row'] == row]
        line = assemble_row(items, budget)
        if line:
            out_lines.append(line)
    if out_lines:
        print('\n'.join(out_lines))

def assemble_row(items, budget):
    # Zone order: by each group's max priority desc; within a zone by priority desc.
    groups = {}
    for it in items:
        groups.setdefault(it['group'], []).append(it)
    for g in groups.values():
        g.sort(key=lambda x: -x['pri'])
    # Display order: fixed semantic rank (stable). Tiebreak by priority.
    zones = sorted(groups.values(),
                   key=lambda g: (ZONE_RANK.get(g[0]['group'], 99), -max(x['pri'] for x in g)))

    variant = {id(it): 'text' for it in items}

    def measure(zs):
        zparts = []
        for z in zs:
            zparts.append(sum(vwidth(it[variant[id(it)]]) for it in z)
                          + len(INTRA) * (len(z) - 1))
        return sum(zparts) + len(ZONE_DIV) * (len(zs) - 1)

    zs = [list(z) for z in zones]

    # 1) shorten lowest-priority regions first
    for it in sorted(items, key=lambda x: x['pri']):
        if measure(zs) <= budget:
            break
        variant[id(it)] = 'short'

    # 2) still over → drop the lowest-priority zone (by its max-priority member),
    #    not necessarily the rightmost — display order stays rank-based.
    while len(zs) > 1 and measure(zs) > budget:
        worst = min(range(len(zs)), key=lambda k: max(x['pri'] for x in zs[k]))
        zs.pop(worst)

    # 3) still over → drop lowest-priority region in the surviving tail zone
    while zs and measure(zs) > budget:
        tail = zs[-1]
        if len(tail) > 1:
            tail.pop(min(range(len(tail)), key=lambda k: tail[k]['pri']))
        else:
            zs.pop()

    if not zs:
        return ''
    rendered_zones = []
    for z in zs:
        rendered_zones.append(INTRA.join(wrap(it[variant[id(it)]], it['color']) for it in z))
    return ZONE_DIV.join(rendered_zones)

if __name__ == '__main__':
    main()
