#!/usr/bin/env python3
"""One editable JSON graph produces Mermaid and SVG; no renderer dependency."""
from pathlib import Path
from html import escape
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/workflows'
GRAPHS = json.loads((OUT / 'diagrams.json').read_text())

def render(graph):
    nodes = {n[0]: n for n in graph['nodes']}
    height = 230 + max(n[3] for n in nodes.values()) * 130
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="{height}" viewBox="0 0 1120 {height}" role="img">',
           '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0 0 L8 4 L0 8Z" fill="#657d8b"/></marker></defs>',
           f'<rect width="1120" height="{height}" fill="#f4f6f5"/>',
           f'<text x="40" y="46" font-size="26" font-family="sans-serif" fill="#183747">{escape(graph["title"])}</text>',
           '<text x="40" y="77" font-size="13" font-family="sans-serif" fill="#526873">HD-2D Waystation / editable source: diagrams.json / generated with make docs</text>']
    mmd = ['flowchart TD']
    for key, lines, col, row in nodes.values():
        label = '<br/>'.join(lines)
        mmd.append(f'    {key}["{label}"]')
    for source, target in graph['edges']:
        a, b = nodes[source], nodes[target]
        ax, ay = 40 + 360 * a[2], 110 + 130 * a[3]
        bx, by = 40 + 360 * b[2], 110 + 130 * b[3]
        if a[3] == b[3]:
            x1, x2 = (ax + 320, bx) if bx > ax else (ax, bx + 320)
            path = f'M{x1} {ay+40} L{x2} {by+40}'
        else:
            middle = (ay + 80 + by) / 2
            path = f'M{ax+160} {ay+80} V{middle} H{bx+160} V{by}'
        svg.append(f'<path d="{path}" fill="none" stroke="#657d8b" stroke-width="2" marker-end="url(#arrow)"/>')
        mmd.append(f'    {source} --> {target}')
    for key, lines, col, row in nodes.values():
        x, y = 40 + 360 * col, 110 + 130 * row
        svg.append(f'<rect x="{x}" y="{y}" width="320" height="80" rx="8" fill="#ffffff" stroke="#a9bbc0"/>')
        for i, line in enumerate(lines):
            size = 17 if i == 0 else 14
            svg.append(f'<text x="{x+160}" y="{y+31+i*26}" text-anchor="middle" font-size="{size}" font-family="sans-serif" fill="#183747">{escape(line)}</text>')
    svg.append('</svg>')
    (OUT / (graph['id'] + '.svg')).write_text('\n'.join(svg) + '\n')
    (OUT / (graph['id'] + '.mmd')).write_text('\n'.join(mmd) + '\n')
    print('DIAGRAM_OK', graph['id'])

for graph in GRAPHS:
    render(graph)
