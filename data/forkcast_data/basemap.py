"""Country borders: download Natural Earth, build the basemaps.

- download: Natural Earth 1:50m countries (as world-atlas TopoJSON) into
  cache/borders/. Public domain.
- build: out/countries.json, the world's 1:50m outlines as TopoJSON (each
  border stored once, quantized: 236 kB gzipped, against 556 kB as GeoJSON).
  The app draws its own basemap from them, so it needs no tile server; it
  decodes them like `countries()` here (web/app/utils/topology.ts).

Usage: uv run python -m forkcast_data download borders | build borders [--fresh]
"""

import json
import sys
from pathlib import Path

from . import pipeline
from .pipeline import CACHE, OUT, Stamp, code_hash, ensure, http_get, log

DIR = CACHE / "borders"
URL = "https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/countries-50m.json"
WORLD = (-180.0, -90.0, 180.0, 90.0)
PAD = 5.0  # degrees around a box


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


def unwrap(r):
    """Keep rings that cross the 180° meridian (Russia, Fiji, the Aleutians)
    whole, on the side where most of their points are, so their fill isn't
    drawn the long way round."""
    xs = [p[0] for p in r]
    if max(xs) - min(xs) <= 180:
        return r
    east = sum(x > 0 for x in xs) >= len(xs) / 2
    return [(x + 360 if east and x < 0 else x - 360 if not east and x > 0 else x, y) for x, y in r]


def in_bbox(r, bbox):
    xs = [p[0] for p in r]
    ys = [p[1] for p in r]
    x0, y0, x1, y1 = bbox[0] - PAD, bbox[1] - PAD, bbox[2] + PAD, bbox[3] + PAD
    return not (max(xs) < x0 or min(xs) > x1 or max(ys) < y0 or min(ys) > y1)


def countries(topo) -> list:
    """Every country as a list of polygons, each a list of rings of (lon, lat)."""
    arcs = decode_arcs(topo)
    out = []
    for g in topo["objects"]["countries"]["geometries"]:
        polys = [g["arcs"]] if g["type"] == "Polygon" else g.get("arcs", []) if g["type"] == "MultiPolygon" else []
        if polys:
            out.append([[unwrap(ring(arcs, r)) for r in poly] for poly in polys])
    return out


def _countries(source: Path) -> None:
    """Publish the TopoJSON with only what the app reads, without whitespace."""
    topo = json.loads(source.read_text())
    geometries = [{"type": g["type"], "arcs": g["arcs"]} for g in topo["objects"]["countries"]["geometries"] if "arcs" in g]
    slim = {"type": "Topology", "transform": topo["transform"], "arcs": topo["arcs"], "objects": {"countries": {"type": "GeometryCollection", "geometries": geometries}}}
    path = OUT / "countries.json"
    path.write_text(json.dumps(slim, separators=(",", ":")))
    print(f"  {len(geometries)} countries, {path.stat().st_size / 1e6:.2f} MB")


SOURCES = {"countries-50m.json": URL}


def _validate_json(key: str):
    def validate(path: Path) -> None:
        data = json.loads(path.read_text())
        if key not in data:
            raise ValueError(f"no '{key}' in {path.name}")

    return validate


def download(fresh: bool = False) -> None:
    for name, url in SOURCES.items():
        log("  " + ensure(DIR / name, lambda to, url=url: http_get(url, to), _validate_json("objects"), fresh))


def outputs() -> list[Path]:
    return [OUT / "countries.json"]


def build(fresh: bool = False) -> None:
    inputs = [DIR / n for n in SOURCES]
    stamp = Stamp("borders", inputs, outputs(), code_hash(sys.modules[__name__], pipeline))
    if not fresh and stamp.up_to_date():
        log("  borders are up to date")
        return
    if stamp.missing_inputs():
        raise SystemExit("Missing border sources. Run: download borders")
    _countries(inputs[0])
    stamp.done()
