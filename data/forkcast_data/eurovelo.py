"""EuroVelo routes from the official GPX tracks in eurovelo/ (see eurovelo/README.md).

Each GPX holds one <trk> per stage, named "NNN: From – To (development status)".
The tracks include variants and spurs, so the route is one path through them
(see chain()). Where consecutive stages don't touch, the hole is bridged with a
straight line: over the sea it is a ferry (not counted as riding), over land an
unmapped stretch (counted, and flagged).

Usage: uv run python -m forkcast_data download eurovelo [--fresh]
  (the route build in routes.py calls build() here)
"""

import gzip
import json
import math
import re
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GPX_DIR = ROOT / "eurovelo"
COUNTRIES = ROOT / "out" / "europe" / "countries.json"
NS = {"g": "http://www.topografix.com/GPX/1/1"}
JOIN_KM = 1.0  # stages closer than this are simply joined

# (number, name, EuroVelo GPX id, map colour)
CATALOG = [
    (1, "Atlantic Coast Route", 2, "#1f77b4"),
    (2, "Capitals Route", 25, "#8c564b"),
    (3, "Pilgrims Route", 26, "#9467bd"),
    (4, "Central Europe Route", 27, "#2ca02c"),
    (5, "Via Romea (Francigena)", 28, "#6b4fbb"),
    (6, "Atlantic – Black Sea", 29, "#17becf"),
    (7, "Sun Route", 30, "#e6a700"),
    (8, "Mediterranean Route", 31, "#d9662b"),
    (9, "Baltic – Adriatic", 32, "#7f7f7f"),
    (10, "Baltic Sea Cycle Route", 33, "#3366cc"),
    (11, "East Europe Route", 34, "#b5179e"),
    (12, "North Sea Cycle Route", 35, "#0b6e4f"),
    (13, "Iron Curtain Trail", 1, "#c0392b"),
    (14, "Waters of Central Europe", 512, "#2a9df4"),
    (15, "Rhine Cycle Route", 36, "#4b7f52"),
    (17, "Rhône Cycle Route", 37, "#a0522d"),
    (19, "Meuse Cycle Route", 135, "#5c6bc0"),
]

STAGE_RE = re.compile(r"^\s*(\d+)\s*:\s*(.*?)\s*(?:\(([^)]*)\))?\s*$")


def haversine_km(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


# --- land test (for telling ferries from unmapped land gaps) -----------------

_land = None


def _load_land():
    gj = json.loads(COUNTRIES.read_text())
    polys = []
    for f in gj["features"]:
        for poly in f["geometry"]["coordinates"]:
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


# --- GPX ---------------------------------------------------------------------


def read_stages(path):
    root = ET.fromstring(gzip.decompress(path.read_bytes()))
    stages = []
    for trk in root.findall("g:trk", NS):
        name = (trk.findtext("g:name", default="", namespaces=NS) or "").strip()
        m = STAGE_RE.match(name)
        num = int(m.group(1)) if m else 10_000 + len(stages)
        title = m.group(2) if m else name
        status = (m.group(3) or "").strip() if m else ""
        pts = []
        for seg in trk.findall("g:trkseg", NS):
            for p in seg.findall("g:trkpt", NS):
                ele = p.findtext("g:ele", namespaces=NS)
                pts.append([float(p.get("lat")), float(p.get("lon")), float(ele) if ele else None])
        if len(pts) >= 2:
            stages.append({"n": num, "title": title, "status": status, "pts": pts})
    stages.sort(key=lambda s: s["n"])
    return stages


def _stage_km(pts):
    return sum(haversine_km(pts[i - 1], pts[i]) for i in range(1, len(pts)))


def chain(stages):
    """Pick one path through the stages and return it as (points, stage spans, gaps).

    Official tracks often contain variants (both river banks, alternatives
    through different countries) and spurs. Stage ends closer than JOIN_KM
    become shared junctions; the route is the shortest path from the start of
    the first stage to the end of the last. Consecutive stages that don't
    touch get a straight "gap" edge, costed high enough that it is only used
    where the track really has a hole (ferries are cheaper than land gaps).
    """
    import heapq

    nodes = []  # junction coordinates

    def node(pt):
        for i, q in enumerate(nodes):
            if haversine_km(pt, q) <= JOIN_KM * 1.5:
                return i
        nodes.append(pt)
        return len(nodes) - 1

    ends = []
    for st in stages:
        ends.append((node(st["pts"][0]), node(st["pts"][-1])))
    adj = {}

    def add(u, v, cost, edge):
        adj.setdefault(u, []).append((v, cost, edge))
        adj.setdefault(v, []).append((u, cost, edge))

    for i, st in enumerate(stages):
        a, b = ends[i]
        if a != b:
            add(a, b, _stage_km(st["pts"]), ("stage", i))
    for i in range(len(stages) - 1):
        cand = [(haversine_km(nodes[x], nodes[y]), x, y) for x in ends[i] for y in ends[i + 1]]
        d, x, y = min(cand)
        if d > JOIN_KM * 1.5:
            ferry = crosses_sea(nodes[x], nodes[y])
            add(x, y, d * (2 if ferry else 8), ("gap", ferry))

    def far_end(i, j):
        """Endpoint of stage i farther from stage j's endpoints."""
        a, b = ends[i]
        da = min(haversine_km(nodes[a], nodes[n]) for n in ends[j])
        db = min(haversine_km(nodes[b], nodes[n]) for n in ends[j])
        return a if da >= db else b

    if len(stages) == 1:
        src, dst = ends[0]
    else:
        src, dst = far_end(0, 1), far_end(len(stages) - 1, len(stages) - 2)
    closing = None
    if src == dst:
        # A loop (EV10 around the Baltic): find the way to the last stage's
        # other end without using it, then close the loop with that stage.
        last = len(stages) - 1
        other = ends[last][1] if ends[last][0] == dst else ends[last][0]
        closing = (other, dst, ("stage", last))
        for n in ends[last]:
            adj[n] = [e for e in adj.get(n, []) if e[2] != ("stage", last)]
        dst = other

    dist = {src: 0.0}
    prev = {}
    pq = [(0.0, src)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == dst:
            break
        if d > dist.get(u, float("inf")):
            continue
        for v, cost, edge in adj.get(u, []):
            nd = d + cost
            if nd < dist.get(v, float("inf")):
                dist[v] = nd
                prev[v] = (u, edge)
                heapq.heappush(pq, (nd, v))
    if dst not in prev and src != dst:
        raise RuntimeError("stages do not form a connected route")
    steps = []
    v = dst
    while v != src:
        u, edge = prev[v]
        steps.append((u, v, edge))
        v = u
    steps.reverse()
    if closing:
        steps.append(closing)

    points = []  # [lat, lon, ele, kind]  kind: 0 track, 1 ferry, 2 unmapped gap
    spans = []
    gaps = []
    pending_gap = None
    for u, v, edge in steps:
        if edge[0] == "gap":
            pending_gap = 1 if edge[1] else 2
            continue
        st = stages[edge[1]]
        pts = st["pts"] if ends[edge[1]][0] == u else st["pts"][::-1]
        if not points:
            start_idx = 0
            body = [[*p, 0] for p in pts]
        else:
            gap_km = haversine_km(points[-1], pts[0])
            if pending_gap or gap_km > JOIN_KM:
                # The straight line into pts[0] is the gap; the stage starts at pts[0].
                kind = pending_gap or (1 if crosses_sea(points[-1], pts[0]) else 2)
                gaps.append({"after": spans[-1][0]["n"], "km": round(gap_km, 1), "ferry": kind == 1})
                start_idx = len(points)
                body = [[pts[0][0], pts[0][1], pts[0][2], kind]] + [[*p, 0] for p in pts[1:]]
            else:
                # Joined: the stage starts at the previous stage's last point.
                start_idx = len(points) - 1
                body = [[*p, 0] for p in pts[1:]]
        pending_gap = None
        points.extend(body)
        spans.append((st, start_idx, len(points) - 1))
    return points, spans, gaps


def build(simplify, out_dir):
    """Write out/routes/ev<N>.json for every catalogued route; return index entries."""
    out_dir.mkdir(parents=True, exist_ok=True)
    index = []
    for number, name, _gpx_id, color in CATALOG:
        path = GPX_DIR / f"ev{number}.gpx.gz"
        if not path.exists():
            print(f"  skip EV{number}: {path.name} missing (run ./build.sh download)")
            continue
        stages = read_stages(path)
        points, spans, gaps = chain(stages)
        # Simplify stage by stage so every stage boundary survives.
        keep = set()
        for _, a, b in spans:
            keep.update(a + i for i in simplify([p[:3] for p in points[a : b + 1]], 30))
        idx = sorted(keep)
        # Cumulative riding km on the full-resolution line (ferries excluded).
        km_full = [0.0]
        for j in range(1, len(points)):
            d = haversine_km(points[j - 1], points[j])
            km_full.append(km_full[-1] + (0.0 if points[j][3] == 1 else d))
        lat = [round(points[j][0], 5) for j in idx]
        lon = [round(points[j][1], 5) for j in idx]
        ele = [None if points[j][2] is None else round(points[j][2]) for j in idx]
        km_at = [round(km_full[j], 2) for j in idx]
        pos = {j: k for k, j in enumerate(idx)}
        ferry = [pos[j] for j in idx if points[j][3] == 1]
        unmapped = [pos[j] for j in idx if points[j][3] == 2]
        total = round(km_full[-1], 1)
        route = {
            "id": f"ev{number}",
            "name": f"EuroVelo {number} – {name}",
            "group": "EuroVelo",
            "continent": "europe",
            "color": color,
            "url": f"https://en.eurovelo.com/ev{number}",
            "source": "EuroVelo GPX tracks (www.EuroVelo.com, downloaded 2026-10-23), ODbL",
            "km": total,
            "lat": lat,
            "lon": lon,
            "ele": ele,
            "km_at": km_at,
            "ferry": ferry,
            "unmapped": unmapped,
        }
        (out_dir / f"ev{number}.json").write_text(json.dumps(route, separators=(",", ":"), ensure_ascii=False))
        ferries = sum(1 for g in gaps if g["ferry"])
        unm = [g for g in gaps if not g["ferry"]]
        print(
            f"  EV{number:<3} {total:8.0f} km  {len(stages):3} stages  {len(lat):6} pts  "
            f"{ferries} ferries  {len(unm)} land gaps ({sum(g['km'] for g in unm):.0f} km)",
            flush=True,
        )
        index.append({k: route[k] for k in ("id", "name", "group", "continent", "color", "url", "km")})
    return index


def _validate_gpx(path: Path) -> None:
    head = gzip.decompress(path.read_bytes())
    if b"<trk>" not in head or b"<trkpt" not in head:
        raise ValueError("no track in the GPX file")


def download(fresh: bool = False) -> None:
    from .pipeline import ensure, http_get, log

    GPX_DIR.mkdir(exist_ok=True)

    def fetch(gpx_id):
        def go(to: Path) -> None:
            raw = to.with_name(to.name + ".raw")
            http_get(f"https://en.eurovelo.com/route/get-gpx/{gpx_id}", raw)
            to.write_bytes(gzip.compress(raw.read_bytes(), compresslevel=9, mtime=0))
            raw.unlink()

        return go

    for number, _name, gpx_id, _color in CATALOG:
        status = ensure(GPX_DIR / f"ev{number}.gpx.gz", fetch(gpx_id), _validate_gpx, fresh)
        log("  " + status)
        if status.startswith("got"):
            time.sleep(2)
