"""EuroVelo routes from OpenStreetMap, where each is a tree of relations: a
superroute `ref=EV<n>` with a part per country, stages below, then ways.

- The route's relations are every relation with that ref that isn't part of
  another one (some countries' parts hang under a national route instead);
  their ways are collected through the tree, leaving out members with a
  role that marks them as not the main line (`SKIP_ROLES`: alternatives,
  variants, excursions, connections).
- The ways make a graph. Pieces that don't touch are bridged with straight
  gap edges between their loose ends: within JOIN_KM simply joined, else a
  ferry over the sea or an unmapped stretch over land, costed higher
  (ferries less than land gaps) so the route only takes one where the
  mapping really has a hole.
- The route is the shortest path through that graph from its official start
  to its end (via points for the loop, EV10), as pinned in CATALOG: OSM
  doesn't say which end is the start, and mapped spurs would otherwise
  stretch it.
- Heights come from the terrain model (dem.py), sampled every STEP_KM and
  smoothed over SMOOTH_KM; OSM has none.

Data © OpenStreetMap contributors, ODbL. EuroVelo® is a registered trademark
of the European Cyclists' Federation.

(the route build in routes.py calls build() here)
"""

import heapq
import json
import math
import re
from collections import defaultdict
from itertools import pairwise

import numpy as np

from . import basemap, dem, osm
from .pipeline import log

COUNTRIES = basemap.DIR / "countries-50m.json"  # the land test's outlines
SKIP_ROLES = frozenset({"alternative", "alternate", "variant", "excursion", "connection", "approach", "link"})
TOUCH_KM = 0.05  # a loose end this close to another piece is joined to it
JOIN_KM = 1.0  # gaps up to this are joined without counting as a gap
NEAREST = 3  # gap edges from each loose end, to the nearest other pieces
FERRY_COST, LAND_GAP_COST = 2.0, 8.0  # per km, against 1 for riding
STEP_KM = 0.05  # heights sampled at least this often
SMOOTH_KM = 0.25  # and averaged over this distance, against the model's noise
SIMPLIFY_M = 30  # kept points: off the simplified line by more than this
CLIMB_M = 5  # or off the simplified height profile by more than this

# (number, name, map colour, [start, via…, end] as (lat, lon)): the official ends.
CATALOG = [
    (1, "Atlantic Coast Route", "#1f77b4", [(71.1694, 25.7833), (37.0089, -8.9469)]),
    (2, "Capitals Route", "#8c564b", [(53.2735, -9.0463), (55.7515, 37.6239)]),
    (3, "Pilgrims Route", "#9467bd", [(63.4271, 10.3953), (42.8806, -8.5446)]),
    (4, "Central Europe Route", "#2ca02c", [(48.7225, -3.9801), (50.4219, 30.5159)]),
    (5, "Via Romea (Francigena)", "#6b4fbb", [(51.2823, 1.0886), (40.6414, 17.9471)]),
    (6, "Atlantic – Black Sea", "#17becf", [(47.2677, -2.1690), (44.1748, 28.6651)]),
    (7, "Sun Route", "#e6a700", [(71.1694, 25.7833), (35.9883, 14.3294)]),
    (8, "Mediterranean Route", "#d9662b", [(36.5232, -6.2878), (37.9455, 27.3423)]),
    (9, "Baltic – Adriatic", "#7f7f7f", [(54.3488, 18.6483), (44.8738, 13.8480)]),
    # A loop round the Baltic, clockwise from Stockholm: Oulu, Riga, Gdańsk, Copenhagen.
    (10, "Baltic Sea Cycle Route", "#3366cc", [(59.3278, 18.0222), (65.0121, 25.4651), (56.9496, 24.1052), (54.3520, 18.6466), (55.6761, 12.5683), (59.3278, 18.0222)]),
    (11, "East Europe Route", "#b5179e", [(71.1694, 25.7833), (37.9767, 23.7262)]),
    (12, "North Sea Cycle Route", "#0b6e4f", [(60.3947, 5.3255), (60.8042, -0.8077)]),
    (13, "Iron Curtain Trail", "#c0392b", [(69.7904, 30.7937), (41.9835, 28.0303)]),
    (14, "Waters of Central Europe", "#2a9df4", [(47.3240, 12.8004), (47.6669, 19.6784)]),
    (15, "Rhine Cycle Route", "#4b7f52", [(46.6371, 8.5949), (51.9873, 4.1045)]),
    (17, "Rhône Cycle Route", "#a0522d", [(46.6371, 8.5949), (43.3950, 3.6948)]),
    (19, "Meuse Cycle Route", "#5c6bc0", [(47.8586, 5.3324), (51.9100, 4.4832)]),
]


def haversine_km(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


# --- land test (for telling ferries from unmapped land gaps) -----------------

_land = None


def _load_land():
    polys = []
    for country in basemap.countries(json.loads(COUNTRIES.read_text())):
        for poly in country:
            ring = poly[0]
            xs = [p[0] for p in ring]
            ys = [p[1] for p in ring]
            polys.append(((min(xs), min(ys), max(xs), max(ys)), ring))
    return polys


def on_land(lat, lon):
    global _land
    if _land is None:
        _land = _load_land()
    for (x0, y0, x1, y1), ring in _land:
        if not (x0 <= lon <= x1 and y0 <= lat <= y1):
            continue
        inside = False
        j = len(ring) - 1
        for i in range(len(ring)):
            xi, yi = ring[i]
            xj, yj = ring[j]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                inside = not inside
            j = i
        if inside:
            return True
    return False


def crosses_sea(a, b, samples=9):
    """A gap is a ferry if most points along it are at sea."""
    sea = 0
    for k in range(1, samples + 1):
        t = k / (samples + 1)
        if not on_land(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t):
            sea += 1
    return sea > samples // 3


# --- From relations to a path -------------------------------------------------


def _refs(tags: dict) -> set[str]:
    return {re.sub(r"\s", "", r).upper() for r in tags.get("ref", "").split(";")}


def roots(rels, number: int) -> list[int]:
    """The relations of EV<number> that are not part of another one of them."""
    ref = f"EV{number}"
    mine = {i for i, (tags, _) in rels.items() if ref in _refs(tags)}
    children = {m for i in mine for kind, m, _ in rels[i][1] if kind == "r"}
    return sorted(mine - children)


def route_ways(rels, number: int) -> list[int]:
    return list(dict.fromkeys(w for r in roots(rels, number) for w in osm.member_ways(rels, r, SKIP_ROLES)))


class Graph:
    """Nodes are OSM node ids; edges carry km, cost and kind (0 ridden, 1 ferry, 2 unmapped gap)."""

    def __init__(self, ways):
        self.at: dict[int, tuple[float, float]] = {}
        self.adj: dict[int, dict[int, tuple[float, float, int]]] = defaultdict(dict)
        for pts in ways:
            for (a, lon1, lat1), (b, lon2, lat2) in pairwise(pts):
                if a != b:
                    self.at[a], self.at[b] = (lat1, lon1), (lat2, lon2)
                    self.add(a, b, 0)

    def add(self, a: int, b: int, kind: int) -> None:
        km = haversine_km(self.at[a], self.at[b])
        cost = km * (1.0, FERRY_COST, LAND_GAP_COST)[kind]
        if b not in self.adj[a] or self.adj[a][b][1] > cost:
            self.adj[a][b] = self.adj[b][a] = (km, cost, kind)

    def pieces(self) -> dict[int, int]:
        """Each node's connected piece, by one of its nodes."""
        piece: dict[int, int] = {}
        for start in self.at:
            if start in piece:
                continue
            piece[start] = start
            stack = [start]
            while stack:
                for v in self.adj[stack.pop()]:
                    if v not in piece:
                        piece[v] = start
                        stack.append(v)
        return piece

    def bridge(self) -> None:
        """Join the pieces: loose ends touching another piece, then gap edges."""
        piece = self.pieces()
        ends = [n for n, nb in self.adj.items() if len(nb) == 1]
        grid: dict[tuple[int, int], list[int]] = defaultdict(list)
        cell = lambda p: (int(math.floor(p[0] * 1000)), int(math.floor(p[1] * 1000)))  # noqa: E731
        for n, p in self.at.items():
            grid[cell(p)].append(n)
        for e in ends:
            y, x = cell(self.at[e])
            near = [n for dy in (-1, 0, 1) for dx in (-1, 0, 1) for n in grid[(y + dy, x + dx)] if piece[n] != piece[e]]
            if near:
                n = min(near, key=lambda n: haversine_km(self.at[e], self.at[n]))
                if haversine_km(self.at[e], self.at[n]) <= TOUCH_KM:
                    self.add(e, n, 0)
        piece = self.pieces()
        ends = [n for n, nb in self.adj.items() if len(nb) == 1]
        if len(set(piece.values())) == 1 or len(ends) < 2:
            return
        ll = np.radians(np.array([self.at[e] for e in ends]))
        pid = np.array([piece[e] for e in ends])
        for i, e in enumerate(ends):
            # Distance to every loose end (haversine), other pieces only.
            dlat, dlon = ll[:, 0] - ll[i, 0], ll[:, 1] - ll[i, 1]
            h = np.sin(dlat / 2) ** 2 + np.cos(ll[i, 0]) * np.cos(ll[:, 0]) * np.sin(dlon / 2) ** 2
            d = 2 * 6371.0088 * np.arcsin(np.sqrt(h))
            d[pid == pid[i]] = np.inf
            seen = set()
            for j in np.argsort(d):
                if not np.isfinite(d[j]) or len(seen) == NEAREST:
                    break
                if pid[j] in seen:
                    continue
                seen.add(pid[j])
                a, b = self.at[e], self.at[ends[j]]
                kind = 0 if d[j] <= JOIN_KM else 1 if crosses_sea(a, b) else 2
                self.add(e, ends[j], kind)

    def nearest(self, p) -> int:
        nodes = list(self.at)
        ll = np.array([self.at[n] for n in nodes])
        d = (ll[:, 0] - p[0]) ** 2 + ((ll[:, 1] - p[1]) * math.cos(math.radians(p[0]))) ** 2
        return nodes[int(np.argmin(d))]

    def path(self, src: int, dst: int) -> list[int]:
        dist, prev = {src: 0.0}, {}
        pq = [(0.0, src)]
        while pq:
            d, u = heapq.heappop(pq)
            if u == dst:
                break
            if d > dist[u]:
                continue
            for v, (_, cost, _) in self.adj[u].items():
                if d + cost < dist.get(v, math.inf):
                    dist[v], prev[v] = d + cost, u
                    heapq.heappush(pq, (d + cost, v))
        if dst != src and dst not in prev:
            raise RuntimeError("the route's pieces could not be joined")
        out = [dst]
        while out[-1] != src:
            out.append(prev[out[-1]])
        return out[::-1]


def _profile_indices(km, ele, tol):
    """Douglas-Peucker on the height profile (km, m): the points that make the climbs."""
    keep = {0, len(km) - 1}
    stack = [(0, len(km) - 1)]
    while stack:
        i, j = stack.pop()
        if j - i < 2:
            continue
        t = (km[i + 1 : j] - km[i]) / max(km[j] - km[i], 1e-9)
        off = np.abs(ele[i + 1 : j] - (ele[i] + (ele[j] - ele[i]) * t))
        k = int(np.argmax(off))
        if off[k] > tol:
            keep.add(i + 1 + k)
            stack += [(i, i + 1 + k), (i + 1 + k, j)]
    return keep


def trace(g: Graph, pins) -> list[list]:
    """The route as [lat, lon, kind] points; kind (1 ferry, 2 unmapped) is the line into the point."""
    nodes = [g.nearest(p) for p in pins]
    walk = [nodes[0]]
    for a, b in pairwise(nodes):
        walk += g.path(a, b)[1:]
    points = [[*g.at[walk[0]], 0]]
    for a, b in pairwise(walk):
        kind = g.adj[a][b][2]
        p, q = g.at[a], g.at[b]
        if kind == 0:
            # Densified, so the heights don't skip a hill between far-apart nodes.
            n = max(1, math.ceil(haversine_km(p, q) / STEP_KM))
            points += [[p[0] + (q[0] - p[0]) * k / n, p[1] + (q[1] - p[1]) * k / n, 0] for k in range(1, n)]
        points.append([*q, kind])
    return points


def build(simplify, out_dir):
    """Write out/routes/ev<N>.json for every catalogued route; return index entries."""
    out_dir.mkdir(parents=True, exist_ok=True)
    rels = osm.relations()
    wanted = {n: route_ways(rels, n) for n, *_ in CATALOG}
    geometry = osm.way_nodes({w for ws in wanted.values() for w in ws})
    heights = dem.Dem()
    index = []
    for number, name, color, pins in CATALOG:
        ways = [geometry[w] for w in wanted[number] if w in geometry]
        if not ways:
            log(f"  skip EV{number}: no ways in OpenStreetMap")
            continue
        g = Graph(ways)
        g.bridge()
        points = trace(g, pins)
        km_full = [0.0]
        for j in range(1, len(points)):
            d = haversine_km(points[j - 1], points[j])
            km_full.append(km_full[-1] + (0.0 if points[j][2] == 1 else d))
        km = np.array(km_full)
        raw = np.array([heights.height(p[0], p[1]) for p in points])
        # Mean over SMOOTH_KM around each point, from cumulative sums.
        csum = np.concatenate([[0.0], np.cumsum(raw)])
        lo = np.searchsorted(km, km - SMOOTH_KM / 2)
        hi = np.searchsorted(km, km + SMOOTH_KM / 2, side="right")
        ele = (csum[hi] - csum[lo]) / (hi - lo)
        # Simplify between gaps, so every gap's ends survive.
        keep = set()
        cuts = [0] + [j for j in range(1, len(points)) if points[j][2]] + [len(points)]
        for a, b in pairwise(cuts):
            run = list(range(a, b))
            keep.update(run[i] for i in simplify([[points[j][0], points[j][1], None] for j in run], SIMPLIFY_M))
            keep.update(run[i] for i in _profile_indices(km[run], ele[run], CLIMB_M))
        idx = sorted(keep)
        pos = {j: k for k, j in enumerate(idx)}
        total = round(km_full[-1], 1)
        route = {
            "id": f"ev{number}",
            "name": f"EuroVelo {number} – {name}",
            "group": "EuroVelo",
            "color": color,
            "url": f"https://en.eurovelo.com/ev{number}",
            "source": "OpenStreetMap (© OpenStreetMap contributors, ODbL); heights: Copernicus GLO-90",
            "km": total,
            "lat": [round(points[j][0], 5) for j in idx],
            "lon": [round(points[j][1], 5) for j in idx],
            "ele": [round(float(ele[j])) for j in idx],
            "km_at": [round(km_full[j], 2) for j in idx],
            "ferry": [pos[j] for j in idx if points[j][2] == 1],
            "unmapped": [pos[j] for j in idx if points[j][2] == 2],
        }
        (out_dir / f"ev{number}.json").write_text(json.dumps(route, separators=(",", ":"), ensure_ascii=False))
        e = route["ele"]
        climb = sum(max(0, b - a) for a, b in pairwise(e))
        gaps = [haversine_km(points[j - 1], points[j]) for j in range(1, len(points)) if points[j][2] == 2]
        log(
            f"  EV{number:<3} {total:8.0f} km  {climb:7.0f} m up  {len(idx):6} pts  {len(route['ferry'])} ferries  "
            f"{len(gaps)} land gaps ({sum(gaps):.0f} km)  from {len(wanted[number])} ways"
        )
        index.append({k: route[k] for k in ("id", "name", "group", "color", "url", "km")})
    return index
