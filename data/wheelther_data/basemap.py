"""Build out/countries.json: Natural Earth 1:50m country outlines for the map area.

The app draws its own basemap from this file, so it needs no tile server.
Source: world-atlas (Natural Earth, public domain), TopoJSON decoded here.

Usage: uv run python -m wheelther_data.basemap
"""

import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out" / "countries.json"
URL = "https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-50m.json"
BBOX = (-30.0, 24.0, 50.0, 75.0)  # lon_min, lat_min, lon_max, lat_max (a bit wider than the climate grid)


def decode_arcs(topo):
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]
    arcs = []
    for arc in topo["arcs"]:
        x = y = 0
        pts = []
        for dx, dy in arc:
            x += dx
            y += dy
            pts.append((x * sx + tx, y * sy + ty))
        arcs.append(pts)
    return arcs


def ring(arcs, idxs):
    pts = []
    for i in idxs:
        a = arcs[i] if i >= 0 else list(reversed(arcs[~i]))
        pts.extend(a if not pts else a[1:])
    return pts


def in_bbox(r):
    xs = [p[0] for p in r]
    ys = [p[1] for p in r]
    return not (max(xs) < BBOX[0] or min(xs) > BBOX[2] or max(ys) < BBOX[1] or min(ys) > BBOX[3])


def main():
    req = urllib.request.Request(URL, headers={"User-Agent": "wheelther-build/0.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        topo = json.load(r)
    arcs = decode_arcs(topo)
    features = []
    for g in topo["objects"]["countries"]["geometries"]:
        polys = [g["arcs"]] if g["type"] == "Polygon" else g.get("arcs", []) if g["type"] == "MultiPolygon" else []
        out = []
        for poly in polys:
            rings = [ring(arcs, r) for r in poly]
            if rings and in_bbox(rings[0]):
                out.append([[[round(x, 3), round(y, 3)] for x, y in r] for r in rings])
        if out:
            features.append({
                "type": "Feature",
                "properties": {"name": g.get("properties", {}).get("name")},
                "geometry": {"type": "MultiPolygon", "coordinates": out},
            })
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"type": "FeatureCollection", "features": features}, separators=(",", ":")))
    print("wrote", OUT, len(features), "countries", f"{OUT.stat().st_size / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
