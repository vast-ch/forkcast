"""Build out/routes/: one JSON file per preset route plus index.json.

- EuroVelo routes come from the official GPX tracks (see eurovelo.py).
- Hand-made routes (anchors.py) are ordered lists of towns; consecutive towns
  are routed with BRouter's "trekking" (touring bike) profile, so distances
  are real riding distances. Legs marked as ferries are straight lines and do
  not count towards the riding distance.

Every BRouter response is cached in cache/brouter/, so re-running only
fetches legs that changed.

Usage: uv run python -m wheelther_data.routes
"""

import hashlib
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

from .anchors import ROUTES

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "cache" / "brouter"
GEOCODED = Path(__file__).with_name("geocoded.json")
OUT_DIR = ROOT / "out" / "routes"
BROUTER = "https://brouter.de/brouter"
UA = "wheelther-build/0.1 (https://github.com/vast-ch/wheelther)"
SIMPLIFY_M = 40  # Douglas-Peucker tolerance


def haversine_km(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0088 * 2 * math.asin(math.sqrt(h))


def brouter_leg(a, b):
    """Return [[lat, lon, ele], ...] for one routed leg."""
    lonlats = f"{a[1]:.5f},{a[0]:.5f}|{b[1]:.5f},{b[0]:.5f}"
    key = hashlib.sha1(lonlats.encode()).hexdigest()[:16]
    path = CACHE / f"{key}.json"
    if not path.exists():
        q = urllib.parse.urlencode({"lonlats": lonlats, "profile": "trekking", "alternativeidx": 0, "format": "geojson"})
        req = urllib.request.Request(f"{BROUTER}?{q}", headers={"User-Agent": UA})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=180) as r:
                    body = r.read()
                break
            except Exception as e:  # noqa: BLE001 - retry any network/server error
                if attempt == 3:
                    raise RuntimeError(f"BRouter failed for {lonlats}: {e}") from e
                time.sleep(5 * (attempt + 1))
        CACHE.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
        time.sleep(1.5)  # be polite to the public server
    gj = json.loads(path.read_text())
    coords = gj["features"][0]["geometry"]["coordinates"]
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
    towns = []
    km = 0.0
    stops = route["stops"]
    for i, stop in enumerate(stops):
        cc, name = stop[0], stop[1]
        ll = geo.get(f"{cc}|{name}")
        if ll is None:
            raise SystemExit(f"Not geocoded: {cc}|{name}")
        towns.append({"name": name.split(",")[0], "km": None, "lat": ll[0], "lon": ll[1]})
        if i == 0:
            points.append([ll[0], ll[1], None, 0.0, False])
            towns[-1]["km"] = 0.0
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
        towns[-1]["km"] = round(km, 1)
        print(f"  {route['id']}: {stops[i - 1][1]} -> {name}{' (ferry)' if ferry else ''}  {km:7.1f} km", flush=True)
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
        "towns": towns,
    }


def main():
    from . import eurovelo

    geo = json.loads(GEOCODED.read_text())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    index = []
    for route in ROUTES:
        print(route["name"], flush=True)
        r = build_route(route, geo)
        (OUT_DIR / f"{r['id']}.json").write_text(json.dumps(r, separators=(",", ":"), ensure_ascii=False))
        index.append({k: r[k] for k in ("id", "name", "group", "color", "url", "km")})
    print("EuroVelo (official GPX tracks)", flush=True)
    index += eurovelo.build(simplify_indices, OUT_DIR)
    (OUT_DIR / "index.json").write_text(json.dumps({"routes": index}, separators=(",", ":"), ensure_ascii=False))
    total = sum(f.stat().st_size for f in OUT_DIR.glob("*.json"))
    print(f"wrote {OUT_DIR} ({len(index)} routes, {total / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
