"""Map details: city and mountain-range names, rivers and lakes.

- download: Natural Earth (public domain) populated places (1:10m), geography
  regions (1:10m, for mountain-range names), rivers and lake centerlines and
  lakes (1:50m) into cache/details/.
- build, per continent:
  - out/<continent>/places.json: {"places": [[name, lon, lat, isCapital]],
    "ranges": [[name, lon, lat]]}. Places are towns of 50,000 or more and
    capitals; a range's name sits at the centre of its area. Every label is
    shown at every zoom: the map's toggles are how a rider thins them out.
  - out/<continent>/water.json: {"rivers": [[[lon, lat], …], …], "lakes":
    [[[lon, lat], …], …]}, coordinates to 0.01° (about 1 km).

The relief shading needs no file: the app draws it from the terrain height in
the climate grid.

Usage: uv run python -m forkcast_data download details | build details [--fresh]
"""

import json
import sys
from pathlib import Path

from . import basemap, continents, pipeline
from .basemap import in_bbox
from .continents import CONTINENTS
from .pipeline import CACHE, OUT, Stamp, code_hash, ensure, http_get, log

DIR = CACHE / "details"
BASE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/"
SOURCES = {
    name: BASE + name
    for name in (
        "ne_10m_populated_places_simple.geojson",
        "ne_10m_geography_regions_polys.geojson",
        "ne_50m_rivers_lake_centerlines.geojson",
        "ne_50m_lakes.geojson",
    )
}
MIN_POPULATION = 50_000


def _validate(path: Path) -> None:
    if not json.loads(path.read_text()).get("features"):
        raise ValueError(f"no features in {path.name}")


def download(fresh: bool = False) -> None:
    for name, url in SOURCES.items():
        log("  " + ensure(DIR / name, lambda to, url=url: http_get(url, to), _validate, fresh))


def outputs() -> list[Path]:
    return [OUT / c["id"] / n for c in CONTINENTS for n in ("places.json", "water.json")]


def _features(name: str) -> list[dict]:
    return json.loads((DIR / name).read_text())["features"]


def _lines(geom: dict) -> list[list]:
    """The lines or outer rings of a geometry, whatever its type."""
    t, c = geom["type"], geom["coordinates"]
    if t == "LineString":
        return [c]
    if t == "MultiLineString":
        return c
    if t == "Polygon":
        return [c[0]]
    if t == "MultiPolygon":
        return [p[0] for p in c]
    return []


def _round(line: list) -> list:
    out = []
    for x, y in line:
        p = [round(x, 2), round(y, 2)]
        if not out or out[-1] != p:
            out.append(p)
    return out


def _centre(rings: list[list]) -> tuple[float, float]:
    """Centre of the largest ring's bounding box: where a range's name goes."""
    ring = max(rings, key=len)
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2


def _inside(lon: float, lat: float, bbox) -> bool:
    return bbox[0] <= lon <= bbox[2] and bbox[1] <= lat <= bbox[3]


def _places(bbox) -> dict:
    places = []
    for f in _features("ne_10m_populated_places_simple.geojson"):
        p = f["properties"]
        lon, lat = f["geometry"]["coordinates"][:2]
        is_capital = p.get("adm0cap") == 1
        if not _inside(lon, lat, bbox) or (p.get("pop_max", 0) < MIN_POPULATION and not is_capital):
            continue
        places.append([p["name"], round(lon, 3), round(lat, 3), int(is_capital)])
    # Capitals first, then by size, so the biggest names draw on top.
    places.sort(key=lambda r: -r[3])
    ranges = []
    for f in _features("ne_10m_geography_regions_polys.geojson"):
        p = f["properties"]
        if p.get("FEATURECLA") != "Range/mtn":
            continue
        lon, lat = _centre(_lines(f["geometry"]))
        if _inside(lon, lat, bbox):
            ranges.append([p["NAME"], round(lon, 2), round(lat, 2)])
    return {"places": places, "ranges": ranges}


def _water(bbox) -> dict:
    def keep(name: str) -> list:
        out = []
        for f in _features(name):
            for line in _lines(f["geometry"]):
                if len(line) > 1 and in_bbox(line, bbox):
                    r = _round(line)
                    if len(r) > 1:
                        out.append(r)
        return out

    return {"rivers": keep("ne_50m_rivers_lake_centerlines.geojson"), "lakes": keep("ne_50m_lakes.geojson")}


def build(fresh: bool = False) -> None:
    inputs = [DIR / n for n in SOURCES]
    stamp = Stamp("details", inputs, outputs(), code_hash(sys.modules[__name__], basemap, continents, pipeline))
    if not fresh and stamp.up_to_date():
        log("  map details are up to date")
        return
    if stamp.missing_inputs():
        raise SystemExit("Missing map-detail sources. Run: download details")
    for c in CONTINENTS:
        folder = OUT / c["id"]
        folder.mkdir(parents=True, exist_ok=True)
        places = _places(c["bbox"])
        water = _water(c["bbox"])
        (folder / "places.json").write_text(json.dumps(places, ensure_ascii=False, separators=(",", ":")))
        (folder / "water.json").write_text(json.dumps(water, separators=(",", ":")))
        size = sum((folder / n).stat().st_size for n in ("places.json", "water.json"))
        log(
            f"  {c['id']:14} {len(places['places']):4} places, {len(places['ranges']):3} ranges, "
            f"{len(water['rivers']):4} rivers, {len(water['lakes']):3} lakes, {size / 1e3:.0f} kB"
        )
    stamp.done()
