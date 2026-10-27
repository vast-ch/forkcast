"""Map details: city names, rivers and lakes.

- download: Natural Earth (public domain) populated places (1:10m), rivers and
  lake centerlines and
  lakes (1:50m) into cache/details/.
- build, per continent:
  - out/<continent>/places.json: {"places": [[name, lon, lat, isCapital,
    population, rank]]}. Places are towns of
    50,000 or more and capitals; rank is a town's place by size in its country
    (1 for the biggest), counted over the whole world so a country split
    between continents ranks the same in both. The map's city setting (off, the 10 biggest per
    country, or over 500,000) picks the towns, and zoomed out only capitals
    keep their names.
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


def _inside(lon: float, lat: float, bbox) -> bool:
    return bbox[0] <= lon <= bbox[2] and bbox[1] <= lat <= bbox[3]


def _ranks() -> dict[str, int]:
    """Each place's rank by population within its country, 1 for the biggest, by name and country."""
    by_country: dict[str, list[tuple[int, str]]] = {}
    for f in _features("ne_10m_populated_places_simple.geojson"):
        p = f["properties"]
        by_country.setdefault(p["adm0name"], []).append((p.get("pop_max", 0), p["name"]))
    ranks = {}
    for country, towns in by_country.items():
        for i, (_, name) in enumerate(sorted(towns, reverse=True)):
            ranks.setdefault(f"{country}/{name}", i + 1)
    return ranks


def _places(bbox) -> dict:
    ranks = _ranks()
    places = []
    for f in _features("ne_10m_populated_places_simple.geojson"):
        p = f["properties"]
        lon, lat = f["geometry"]["coordinates"][:2]
        is_capital = p.get("adm0cap") == 1
        pop = p.get("pop_max", 0)
        if not _inside(lon, lat, bbox) or (pop < MIN_POPULATION and not is_capital):
            continue
        rank = ranks[f"{p['adm0name']}/{p['name']}"]
        places.append([p["name"], round(lon, 3), round(lat, 3), int(is_capital), pop, rank])
    # Capitals first, then by size, so the biggest names draw on top.
    places.sort(key=lambda r: (-r[3], -r[4]))
    return {"places": places}


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
            f"  {c['id']:14} {len(places['places']):4} places, "
            f"{len(water['rivers']):4} rivers, {len(water['lakes']):3} lakes, {size / 1e3:.0f} kB"
        )
    stamp.done()
