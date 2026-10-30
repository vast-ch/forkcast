"""Cycle network: OpenStreetMap's international bicycle routes, for drawing
routes that follow them (the app snaps clicks to it and routes along it).

- build: out/cyclenet.json, {"lines": [[[lon, lat], …], …]}: the ways of
  every international route (network icn: in Europe essentially EuroVelo,
  elsewhere little) and of its child routes, from the bicycle routes cut out
  of the OpenStreetMap planet (osm.py), each way once, joined end to end
  into long lines where exactly two meet, simplified to about 300 m and
  rounded to 0.001° (about 100 m). The app fetches it only when the rider
  draws with snapping on.

Data © OpenStreetMap contributors, ODbL: credited on the map and the help page.

Usage: uv run python -m forkcast_data build cyclenet [--fresh]
"""

import gzip
import json
import math
import sys
from pathlib import Path

from . import osm, pipeline
from .pipeline import OUT, Stamp, code_hash, log

NETWORKS = ("icn",)
SIMPLIFY = 0.003  # degrees, about 300 m
GAP = 0.0015  # degrees, about 150 m: line ends this close are joined


def outputs() -> list[Path]:
    return [OUT / "cyclenet.json"]


def _simplify(line: list, tol: float) -> list:
    """Douglas–Peucker in degrees: keep the points that bend the line."""
    if len(line) < 3:
        return line
    keep = [False] * len(line)
    keep[0] = keep[-1] = True
    stack = [(0, len(line) - 1)]
    while stack:
        a, b = stack.pop()
        (x1, y1), (x2, y2) = line[a], line[b]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy) or 1e-12
        far, at = 0.0, -1
        for i in range(a + 1, b):
            x, y = line[i]
            d = abs(dy * (x - x1) - dx * (y - y1)) / length
            if d > far:
                far, at = d, i
        if far > tol:
            keep[at] = True
            stack += [(a, at), (at, b)]
    return [p for p, k in zip(line, keep, strict=True) if k]


def _split_at_junctions(ways: list[list]) -> list[list]:
    """Split ways at every point another way shares, so junctions are line
    ends: in OSM one route often meets another part-way along a way, and
    simplifying would otherwise drop that point and cut the network apart."""
    key = lambda p: (round(p[0], 6), round(p[1], 6))  # noqa: E731
    used: dict[tuple, int] = {}
    for w in ways:
        for k in {key(p) for p in w}:
            used[k] = used.get(k, 0) + 1
    out = []
    for w in ways:
        start = 0
        for i in range(1, len(w) - 1):
            if used[key(w[i])] > 1:
                out.append(w[start : i + 1])
                start = i
        out.append(w[start:])
    return out


def _close_gaps(lines: list[list], tol: float = GAP) -> list[list]:
    """Move line ends that are within `tol` degrees of each other onto one
    point, so routes that OSM maps as separate sections meeting a few metres
    apart (often at borders) connect."""
    cell = lambda p: (math.floor(p[0] / tol), math.floor(p[1] / tol))  # noqa: E731
    ends = [(i, j) for i, line in enumerate(lines) for j in (0, len(line) - 1)]
    grid: dict[tuple, list[int]] = {}
    for k, (i, j) in enumerate(ends):
        grid.setdefault(cell(lines[i][j]), []).append(k)
    parent = list(range(len(ends)))

    def find(k: int) -> int:
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    for k, (i, j) in enumerate(ends):
        x, y = lines[i][j]
        cx, cy = cell(lines[i][j])
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for m in grid.get((cx + dx, cy + dy), []):
                    a, b = ends[m]
                    if a != i and math.hypot(lines[a][b][0] - x, lines[a][b][1] - y) <= tol:
                        parent[find(k)] = find(m)
    target = {}
    for k, (i, j) in enumerate(ends):
        target.setdefault(find(k), lines[i][j])
    for k, (i, j) in enumerate(ends):
        lines[i][j] = target[find(k)]
    return lines


def _join(ways: list[list]) -> list[list]:
    """Join ways end to end where exactly two meet, so a route that OSM splits
    into many short ways becomes one long line (simplifying then works, and
    the file shrinks). Junctions of three or more stay line ends."""
    key = lambda p: (round(p[0], 6), round(p[1], 6))  # noqa: E731
    ends: dict[tuple, list[int]] = {}
    for i, w in enumerate(ways):
        for p in (w[0], w[-1]):
            ends.setdefault(key(p), []).append(i)
    used = [False] * len(ways)
    lines = []
    for start in range(len(ways)):
        if used[start]:
            continue
        used[start] = True
        line = list(ways[start])
        for forward in (True, False):
            while True:
                tip = key(line[-1] if forward else line[0])
                nxt = [j for j in ends.get(tip, []) if not used[j]]
                if len(ends.get(tip, [])) != 2 or not nxt:
                    break
                j = nxt[0]
                used[j] = True
                w = ways[j]
                if forward:
                    # Append: the way must start at the tip.
                    line += (w if key(w[0]) == tip else w[::-1])[1:]
                else:
                    # Prepend: the way must end at the tip.
                    line = (w if key(w[-1]) == tip else w[::-1])[:-1] + line
        lines.append(line)
    return lines


def build(fresh: bool = False) -> None:
    if not osm.BICYCLE.exists():
        raise SystemExit("Missing the bicycle routes. Run: download osm, build bicycle")
    stamp = Stamp("cyclenet", [osm.BICYCLE], outputs(), code_hash(sys.modules[__name__], osm, pipeline), {"networks": NETWORKS})
    if not fresh and stamp.up_to_date():
        log("  cycle network is up to date")
        return
    rels = osm.relations()
    roots = [i for i, (tags, _) in rels.items() if tags.get("network") in NETWORKS]
    ids = {w for r in roots for w in osm.member_ways(rels, r)}
    ways = [[(lon, lat) for _, lon, lat in pts] for pts in osm.way_nodes(ids).values()]
    log(f"  {len(roots)} routes, {len(ways)} ways")
    lines = []
    points = 0
    for coords in _join(_split_at_junctions(ways)):
        line = [[round(x, 3), round(y, 3)] for x, y in _simplify(coords, SIMPLIFY)]
        line = [p for i, p in enumerate(line) if i == 0 or p != line[i - 1]]
        if len(line) > 1:
            lines.append(line)
            points += len(line)
    lines = _close_gaps(lines)
    path = OUT / "cyclenet.json"
    path.write_text(json.dumps({"lines": lines}, separators=(",", ":")))
    gz = len(gzip.compress(path.read_bytes(), 9))
    log(f"  {len(ways)} ways -> {len(lines)} lines, {points} points, {path.stat().st_size / 1e6:.2f} MB ({gz / 1e6:.2f} MB gzipped)")
    stamp.done()
