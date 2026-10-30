"""Terrain height for the routes built from OpenStreetMap, which has none.

- download `dem`: the Copernicus GLO-90 digital elevation model (3 arc
  seconds, about 90 m) from its open bucket on AWS, as one GeoTIFF per 1°
  square, for every square of AREA that has land: about 1,700 files, 5 GB,
  in cache/dem/.
- `Dem().height(lat, lon)`: bilinear height in metres; 0 at sea (no square).

It is a surface model (tree tops and roofs, not the ground), like the SRTM
that BRouter gives the hand-made routes: along cycle routes, mostly roads
and riversides, the difference is small, and climbing is counted from it
after smoothing out the metre-scale noise.

Copernicus DEM © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH
2014–2018, provided under COPERNICUS by the European Union and ESA.
"""

from __future__ import annotations

import math
import re
from pathlib import Path

from .pipeline import CACHE, ensure, http_get, is_verified, log

DIR = CACHE / "dem"
BUCKET = "https://copernicus-dem-90m.s3.amazonaws.com/"
LIST = DIR / "tileList.txt"
# Where the preset routes are (EuroVelo): south, west, north, east, in whole degrees.
AREA = (34, -32, 72, 45)


def _name(lat: int, lon: int) -> str:
    ns, ew = ("N" if lat >= 0 else "S"), ("E" if lon >= 0 else "W")
    return f"Copernicus_DSM_COG_30_{ns}{abs(lat):02d}_00_{ew}{abs(lon):03d}_00_DEM"


def tile_file(name: str) -> Path:
    return DIR / f"{name}.tif"


def tiles() -> list[str]:
    """The squares of AREA that the model has (it has none over the open sea)."""
    have = set(LIST.read_text().split())
    s, w, n, e = AREA
    return [_name(lat, lon) for lat in range(s, n) for lon in range(w, e) if _name(lat, lon) in have]


def _validate_list(path: Path) -> None:
    if not re.search(r"Copernicus_DSM_COG_30_N46_00_E007_00_DEM", path.read_text()):
        raise ValueError("not the tile list")


def _validate_tile(path: Path) -> None:
    with open(path, "rb") as f:
        head = f.read(4)
    if head not in (b"II*\x00", b"II+\x00"):
        raise ValueError("not a GeoTIFF")
    import rasterio

    with rasterio.open(path) as src:
        src.read(1, window=((0, 1), (0, 1)))


def download(fresh: bool = False) -> None:
    log("  " + ensure(LIST, lambda to: http_get(BUCKET + "tileList.txt", to), _validate_list, fresh))
    names = tiles()
    todo = [n for n in names if fresh or not is_verified(tile_file(n))]
    log(f"  {len(names)} squares, {len(names) - len(todo)} downloaded, {len(todo)} to fetch")
    for i, name in enumerate(todo, 1):
        ensure(tile_file(name), lambda to, n=name: http_get(f"{BUCKET}{n}/{n}.tif", to), _validate_tile, fresh)
        if i % 100 == 0:
            log(f"  [{i:4}/{len(todo)}] squares fetched")


def files() -> list[Path]:
    return [LIST] + ([tile_file(n) for n in tiles()] if LIST.exists() else [])


class Dem:
    """Heights from the downloaded squares, each read once when first needed."""

    def __init__(self) -> None:
        self._tiles: dict[tuple[int, int], tuple | None] = {}

    def _tile(self, lat: int, lon: int):
        key = (lat, lon)
        if key not in self._tiles:
            path = tile_file(_name(lat, lon))
            if not path.exists():
                self._tiles[key] = None
            else:
                import rasterio

                with rasterio.open(path) as src:
                    self._tiles[key] = (src.read(1), ~src.transform)
        return self._tiles[key]

    def height(self, lat: float, lon: float) -> float:
        tile = self._tile(math.floor(lat), math.floor(lon))
        if tile is None:
            return 0.0
        a, inv = tile
        # Pixel centres: the model's pixels are areas, so shift by half a pixel.
        x, y = inv * (lon, lat)
        x, y = x - 0.5, y - 0.5
        rows, cols = a.shape
        x0 = min(max(int(math.floor(x)), 0), cols - 2)
        y0 = min(max(int(math.floor(y)), 0), rows - 2)
        fx = min(max(x - x0, 0.0), 1.0)
        fy = min(max(y - y0, 0.0), 1.0)
        top = a[y0, x0] * (1 - fx) + a[y0, x0 + 1] * fx
        bottom = a[y0 + 1, x0] * (1 - fx) + a[y0 + 1, x0 + 1] * fx
        return float(top * (1 - fy) + bottom * fy)

