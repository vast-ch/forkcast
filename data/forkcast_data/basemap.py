"""Build the basemaps.

- out/<continent>/countries.json: Natural Earth 1:50m country outlines per continent.
- out/world.json: one simplified SVG path per continent for the continent picker,
  from Natural Earth 1:110m countries (which tag each country with its continent).

The app draws its own basemap from this file, so it needs no tile server.
Source: world-atlas (Natural Earth, public domain), TopoJSON decoded here.

Usage: uv run python -m forkcast_data.basemap
"""

import json
import urllib.request
from pathlib import Path

from .continents import CONTINENTS

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "out"
URL = "https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-50m.json"
WORLD_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_admin_0_countries.geojson"
# Natural Earth continent names -> our continent ids (others, e.g. Antarctica, are drawn but not clickable)
NE_CONTINENTS = {
    "Europe": "europe",
    "Africa": "africa",
    "Asia": "asia",
    "North America": "north-america",
    "South America": "south-america",
    "Oceania": "oceania",
}
PAD = 5.0  # degrees around each continent's box


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


def unwrap(r, bbox):
    """Keep rings that cross the 180° meridian (Russia, Fiji, the Aleutians) on
    the continent's side, so their fill isn't drawn the long way round."""
    xs = [p[0] for p in r]
    if max(xs) - min(xs) <= 180:
        return r
    east = (bbox[0] + bbox[2]) / 2 > 0
    return [(x + 360 if east and x < 0 else x - 360 if not east and x > 0 else x, y) for x, y in r]


def in_bbox(r, bbox):
    xs = [p[0] for p in r]
    ys = [p[1] for p in r]
    x0, y0, x1, y1 = bbox[0] - PAD, bbox[1] - PAD, bbox[2] + PAD, bbox[3] + PAD
    return not (max(xs) < x0 or min(xs) > x1 or max(ys) < y0 or min(ys) > y1)


def main():
    req = urllib.request.Request(URL, headers={"User-Agent": "forkcast-build/0.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        topo = json.load(r)
    arcs = decode_arcs(topo)
    for c in CONTINENTS:
        features = []
        for g in topo["objects"]["countries"]["geometries"]:
            polys = [g["arcs"]] if g["type"] == "Polygon" else g.get("arcs", []) if g["type"] == "MultiPolygon" else []
            out = []
            for poly in polys:
                rings = [unwrap(ring(arcs, r), c["bbox"]) for r in poly]
                if rings and in_bbox(rings[0], c["bbox"]):
                    out.append([[[round(x, 3), round(y, 3)] for x, y in r] for r in rings])
            if out:
                features.append({
                    "type": "Feature",
                    "properties": {},
                    "geometry": {"type": "MultiPolygon", "coordinates": out},
                })
        path = OUT / c["id"] / "countries.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"type": "FeatureCollection", "features": features}, separators=(",", ":")))
        print(f"  {c['id']:14} {len(features):3} countries, {path.stat().st_size / 1e6:.2f} MB")


def world():
    """One SVG path per continent, equirectangular: x = lon + 180, y = 90 - lat."""
    req = urllib.request.Request(WORLD_URL, headers={"User-Agent": "forkcast-build/0.1"})
    with urllib.request.urlopen(req, timeout=60) as r:
        gj = json.load(r)
    paths = {}
    for f in gj["features"]:
        props = f["properties"]
        # Natural Earth files Russia under Europe; our Asia box covers all of it.
        cont = "Asia" if props.get("ISO_A3") == "RUS" or props.get("ADM0_A3") == "RUS" else props.get("CONTINENT")
        cid = NE_CONTINENTS.get(cont, "other")
        g = f["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for poly in polys:
            ring = poly[0]
            d = "M" + "L".join(f"{lon + 180:.1f},{90 - lat:.1f}" for lon, lat in ring) + "Z"
            paths.setdefault(cid, []).append(d)
    out = {cid: "".join(ds) for cid, ds in paths.items()}
    path = OUT / "world.json"
    path.write_text(json.dumps(out, separators=(",", ":")))
    print(f"  world          {len(out)} continents, {path.stat().st_size / 1e3:.0f} kB")


if __name__ == "__main__":
    main()
    world()
