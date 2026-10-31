"""Build out/routes/: one JSON file per preset route plus index.json.

- EuroVelo routes come from OpenStreetMap's route relations (see eurovelo.py).
- Hand-made routes (anchors.py) are ordered lists of towns; consecutive towns
  are routed with BRouter's "trekking" (touring bike) profile, so distances
  are real riding distances. Legs marked as ferries are straight lines and do
  not count towards the riding distance.

- download (`brouter`): geocodes the hand-made routes' stops (geocode.py)
  and fetches every leg from BRouter into cache/brouter/, one file per leg.
- download (`eurovelo-legs`): the stretches the EuroVelo routes need routed
  (eurovelo.legs(): unmapped gaps, ends the mapping stops short of), listed
  in cache/brouter/eurovelo-legs.json and fetched the same way. It needs the
  bicycle routes, so it builds them first if they are out of date. Where
  BRouter finds no route, the leg file keeps BRouter's answer as an error,
  and the route keeps its straight gap there.
- build (`routes`): reads only cached files, never the network. Besides one
  file per route it writes overview.json, every route simplified to ~1 km, so
  the app can draw all of them on the map cheaply.

Usage: uv run python -m forkcast_data download brouter | download eurovelo-legs | build routes [--fresh]
"""

import hashlib
import json
import math
import sys
import time
import urllib.error
import urllib.parse
from pathlib import Path

from . import anchors, dem, eurovelo, geocode, osm, pipeline
from .anchors import ROUTES
from .eurovelo import haversine_km
from .pipeline import CACHE as CACHE_ROOT
from .pipeline import OUT, Stamp, code_hash, ensure, http_get, log

CACHE = CACHE_ROOT / "brouter"
GEOCODED = geocode.CACHE
OUT_DIR = OUT / "routes"
BROUTER = "https://brouter.de/brouter"
EUROVELO_LEGS = CACHE / "eurovelo-legs.json"
SIMPLIFY_M = 40  # Douglas-Peucker tolerance


def _lonlats(a, b) -> str:
    return f"{a[1]:.5f},{a[0]:.5f}|{b[1]:.5f},{b[0]:.5f}"


def leg_path(a, b) -> Path:
    return CACHE / f"{hashlib.sha1(_lonlats(a, b).encode()).hexdigest()[:16]}.json"


def _validate_leg(path: Path) -> None:
    gj = json.loads(path.read_text())
    coords = gj["features"][0]["geometry"]["coordinates"]
    if len(coords) < 2:
        raise ValueError("leg has fewer than two points")


def legs(geo):
    """All routed (non-ferry) legs of the hand-made routes, as (from, to) coordinates."""
    for route in ROUTES:
        stops = route["stops"]
        for i in range(1, len(stops)):
            if len(stops[i]) > 2 and stops[i][2] == "ferry":
                continue
            a = geo[f"{stops[i - 1][0]}|{stops[i - 1][1]}"]
            b = geo[f"{stops[i][0]}|{stops[i][1]}"]
            yield a, b


def _fetch(a, b, fresh: bool, may_fail: bool = False) -> None:
    q = urllib.parse.urlencode({"lonlats": _lonlats(a, b), "profile": "trekking", "alternativeidx": 0, "format": "geojson"})

    def fetch(to):
        try:
            http_get(f"{BROUTER}?{q}", to, timeout=300)
        except urllib.error.HTTPError as e:
            if not may_fail or e.code == 429:
                raise
            # BRouter says why it found no route (e.g. "to-position not mapped"): kept, so it isn't asked again.
            to.write_text(json.dumps({"error": e.read().decode(errors="replace")[:500]}))

    status = ensure(leg_path(a, b), fetch, _validate_ev_leg if may_fail else _validate_leg, fresh)
    if status.startswith("got"):
        log(f"  {status} ({_lonlats(a, b)})")
        time.sleep(1.5)  # be polite to the public server


def _validate_ev_leg(path: Path) -> None:
    if "error" not in json.loads(path.read_text()):
        _validate_leg(path)


def download(fresh: bool = False) -> None:
    geocode.main(fresh)
    geo = json.loads(GEOCODED.read_text())
    for a, b in legs(geo):
        _fetch(a, b, fresh)
    log("  BRouter legs ready")


def download_eurovelo(fresh: bool = False) -> None:
    osm.build()
    wanted = eurovelo.legs()
    CACHE.mkdir(parents=True, exist_ok=True)
    EUROVELO_LEGS.write_text(json.dumps(wanted))
    for a, b in wanted:
        _fetch(a, b, fresh, may_fail=True)
    failed = sum("error" in json.loads(leg_path(a, b).read_text()) for a, b in wanted)
    log(f"  {len(wanted)} EuroVelo legs ready, {failed} without a route")


def eurovelo_leg(a, b):
    """The cached leg for a EuroVelo fill as [[lat, lon], ...], or None where BRouter found no route."""
    path = leg_path(a, b)
    if not path.exists():
        raise SystemExit(f"Missing BRouter leg {path.name} for EuroVelo. Run: download eurovelo-legs")
    gj = json.loads(path.read_text())
    if "error" in gj:
        return None
    return [[c[1], c[0]] for c in gj["features"][0]["geometry"]["coordinates"]]


def brouter_leg(a, b):
    """Return [[lat, lon, ele], ...] for one cached leg."""
    path = leg_path(a, b)
    if not path.exists():
        raise SystemExit(f"Missing BRouter leg {path.name}. Run: download brouter")
    coords = json.loads(path.read_text())["features"][0]["geometry"]["coordinates"]
    return [[c[1], c[0], c[2] if len(c) > 2 else None] for c in coords]


def simplify_indices(points, tol_m):
    """Douglas-Peucker on an equirectangular projection; returns kept indices (endpoints included)."""
    if len(points) < 3:
        return list(range(len(points)))
    lat0 = math.radians(sum(p[0] for p in points) / len(points))
    xy = [(math.radians(p[1]) * math.cos(lat0) * 6371000, math.radians(p[0]) * 6371000) for p in points]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        i, j = stack.pop()
        (x1, y1), (x2, y2) = xy[i], xy[j]
        dx, dy = x2 - x1, y2 - y1
        norm = math.hypot(dx, dy) or 1e-9
        best, idx = 0.0, -1
        for k in range(i + 1, j):
            x, y = xy[k]
            d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / norm
            if d > best:
                best, idx = d, k
        if best > tol_m and idx > 0:
            keep[idx] = True
            stack += [(i, idx), (idx, j)]
    return [i for i, k in enumerate(keep) if k]


def simplify(points, tol_m):
    return [points[i] for i in simplify_indices(points, tol_m)]


def build_route(route, geo):
    points = []  # [lat, lon, ele, km, ferry]
    km = 0.0
    stops = route["stops"]
    for i, stop in enumerate(stops):
        cc, name = stop[0], stop[1]
        ll = geo.get(f"{cc}|{name}")
        if ll is None:
            raise SystemExit(f"Not geocoded: {cc}|{name}")
        if i == 0:
            points.append([ll[0], ll[1], None, 0.0, False])
            continue
        prev = geo[f"{stops[i - 1][0]}|{stops[i - 1][1]}"]
        ferry = len(stop) > 2 and stop[2] == "ferry"
        leg = [[prev[0], prev[1], None], [ll[0], ll[1], None]] if ferry else brouter_leg(prev, ll)
        leg = simplify(leg, SIMPLIFY_M)
        for p in leg[1:]:
            last = points[-1]
            if not ferry:
                km += haversine_km(last, p)
            points.append([p[0], p[1], p[2], km, ferry])
    return {
        "id": route["id"],
        "name": route["name"],
        "group": route.get("group", "Demo"),
        "color": route["color"],
        "url": route["url"],
        "source": "Routed with BRouter (trekking profile) on OpenStreetMap data",
        "km": round(km, 1),
        # Compact columns: lat, lon (5 dp), elevation (m), cumulative km (0.01), ferry flag.
        "lat": [round(p[0], 5) for p in points],
        "lon": [round(p[1], 5) for p in points],
        "ele": [None if p[2] is None else round(p[2]) for p in points],
        "km_at": [round(p[3], 2) for p in points],
        "ferry": [i for i, p in enumerate(points) if p[4]],
    }


OVERVIEW_M = 1000  # simplification for the map's overview of all routes


def write_overview(index) -> None:
    """out/routes/overview.json: every preset route simplified to ~1 km, for drawing
    all of them on the map without downloading each full track."""
    routes = []
    for meta in index:
        r = json.loads((OUT_DIR / f"{meta['id']}.json").read_text())
        pts = [[la, lo, None] for la, lo in zip(r["lat"], r["lon"], strict=True)]
        keep = simplify_indices(pts, OVERVIEW_M)
        routes.append({
            "id": r["id"],
            "color": r["color"],
            "lat": [round(r["lat"][i], 3) for i in keep],
            "lon": [round(r["lon"][i], 3) for i in keep],
        })
    path = OUT_DIR / "overview.json"
    path.write_text(json.dumps({"routes": routes}, separators=(",", ":")))
    log(f"  wrote overview of {len(routes)} routes ({path.stat().st_size / 1e3:.0f} kB)")


def outputs() -> list[Path]:
    ids = [r["id"] for r in ROUTES] + [f"ev{c[0]}" for c in eurovelo.CATALOG]
    return [OUT_DIR / f"{i}.json" for i in ids] + [OUT_DIR / "index.json", OUT_DIR / "overview.json"]


def build(fresh: bool = False) -> None:
    geo = json.loads(GEOCODED.read_text())
    inputs = [GEOCODED, eurovelo.COUNTRIES, osm.BICYCLE, *dem.files()]
    inputs += [leg_path(a, b) for a, b in legs(geo)]
    if EUROVELO_LEGS.exists():
        inputs += [EUROVELO_LEGS] + [leg_path(a, b) for a, b in json.loads(EUROVELO_LEGS.read_text())]
    else:
        inputs.append(EUROVELO_LEGS)
    code = code_hash(sys.modules[__name__], eurovelo, osm, dem, anchors, pipeline)
    stamp = Stamp("routes", inputs, outputs(), code)
    if not fresh and stamp.up_to_date():
        log("  routes are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing route inputs ({missing[0].name}, …). Run: download osm, download dem, download brouter, download eurovelo-legs, build borders")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    index = []
    for route in ROUTES:
        log(route["name"])
        r = build_route(route, geo)
        (OUT_DIR / f"{r['id']}.json").write_text(json.dumps(r, separators=(",", ":"), ensure_ascii=False))
        index.append({k: r[k] for k in ("id", "name", "group", "color", "url", "km")})
    log("EuroVelo (OpenStreetMap)")
    index += eurovelo.build(simplify_indices, OUT_DIR, eurovelo_leg)
    (OUT_DIR / "index.json").write_text(json.dumps({"routes": index}, separators=(",", ":"), ensure_ascii=False))
    write_overview(index)
    stamp.done()
    total = sum(f.stat().st_size for f in OUT_DIR.glob("*.json"))
    log(f"  wrote {OUT_DIR.relative_to(pipeline.ROOT)} ({len(index)} routes, {total / 1e6:.1f} MB)")
