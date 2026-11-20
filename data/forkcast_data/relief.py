"""The map's relief shading: terrain heights at 0.05° in 10° tiles.

The climate tiles carry each 0.25° cell's mean height (for the altitude
correction), but shading from those blurred valleys and ranges into 25 km
blobs. The relief has its own terrain: NOAA's ETOPO 2022, a world-wide
elevation model at 1 arc-minute (about 1.8 km), averaged to 0.05° (about
5.5 km), in the same 10° squares as the climate, so the app fetches a
square's relief only with its climate tile and only while the Relief layer is
on.

- download `etopo`: ETOPO 2022's surface elevation at 60 arc-seconds, one
  netCDF of the world (cache/etopo/, 478 MB). Public domain (NOAA NCEI).
- build `relief`: out/relief.json (step, tile, size, which tiles exist) and
  out/relief/<lat>_<lon>.bin for each 10° tile the climate has (by its
  south-west corner, like the climate's): SIZE × SIZE heights from the
  north-west corner, rows north to south, sharing their edges with the
  neighbours, each a little-endian int16 in metres (about 80 KB a tile). Each
  height is the mean of the 3′ box around its point (3 × 3 of ETOPO's 1′
  cells, the edge ones counted half). ETOPO has the sea floor too: anything
  below sea level is 0, flat, so it shades as nothing (and the app draws only
  on the climate's land).

Usage: uv run python -m forkcast_data download etopo [--fresh]
       uv run python -m forkcast_data build relief [--fresh]
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np

from . import pack, pipeline
from .pack import TILE
from .pipeline import CACHE, OUT, Stamp, code_hash, ensure, http_get, log

URL = "https://www.ngdc.noaa.gov/thredds/fileServer/global/ETOPO2022/60s/60s_surface_elev_netcdf/ETOPO_2022_v1_60s_N90W180_surface.nc"
SOURCE = CACHE / "etopo" / "ETOPO_2022_v1_60s_N90W180_surface.nc"
DIR = OUT / "relief"
HEADER = OUT / "relief.json"
STEP = 0.05
SIZE = round(TILE / STEP) + 1
PER = 3  # ETOPO's 1′ cells per STEP
# ETOPO's cell i is centred 1/120° past i arc-minutes, so a point on a 0.05°
# multiple (3k′) sits between cells 3k − 1 and 3k: its 3′ box is those two,
# and half of the one on either side.
TAPS = np.array([-2, -1, 0, 1])
WEIGHTS = np.array([0.5, 1, 1, 0.5]) / PER


def _validate(path: Path) -> None:
    import xarray as xr

    with xr.open_dataset(path) as ds:
        z = ds["z"]
        if z.sizes.get("lat") != 180 * 60 or z.sizes.get("lon") != 360 * 60:
            raise ValueError("not the world at 1 arc-minute")
        if not 8000 < float(z.max()) < 9000:  # Everest, 8,849 m
            raise ValueError("no Himalaya in the terrain file")


def download(fresh: bool = False) -> None:
    log("  " + ensure(SOURCE, lambda to: http_get(URL, to, timeout=1800), _validate, fresh))


def cut(z: np.ndarray, lat: int, lon: int) -> np.ndarray:
    """A tile's SIZE × SIZE heights (m, none below 0), from its north-west corner,
    out of the 1′ grid `z` (rows from 90° S, columns from 180° W). Columns wrap
    round at 180°; rows past a pole repeat the last."""
    k = round((lat + TILE + 90) / STEP) - np.arange(SIZE)  # the points' rows, north to south
    j = round((lon + 180) / STEP) + np.arange(SIZE)
    r = np.clip(PER * k[:, None] + TAPS, 0, z.shape[0] - 1).ravel()
    c = ((PER * j[:, None] + TAPS) % z.shape[1]).ravel()
    cells = z[np.ix_(r, c)].astype(np.float64).reshape(SIZE, len(TAPS), SIZE, len(TAPS))
    return np.maximum(np.einsum("a,b,iajb->ij", WEIGHTS, WEIGHTS, cells), 0)


def encode(tile: np.ndarray) -> bytes:
    return np.clip(np.round(tile), -32768, 32767).astype("<i2").tobytes()


def build(fresh: bool = False) -> None:
    climate = pack.header_file("last15")
    stamp = Stamp("relief", [SOURCE, climate], [HEADER], code_hash(sys.modules[__name__], pack, pipeline))
    if not fresh and stamp.up_to_date():
        log("  relief is up to date")
        return
    if stamp.missing_inputs():
        raise SystemExit("Missing the terrain or the climate. Run: download etopo, build pack")
    import xarray as xr

    with xr.open_dataset(SOURCE) as ds:
        z = ds["z"].values  # rows from 90° S, columns from 180° W
    if DIR.exists():
        shutil.rmtree(DIR)
    DIR.mkdir(parents=True)
    # The same squares as the climate: the app asks for a square's relief with its climate tile.
    ids = sorted(json.loads(climate.read_text())["tiles"])
    for tid in ids:
        lat, lon = map(int, tid.split("_"))
        (DIR / f"{tid}.bin").write_bytes(encode(cut(z, lat, lon)))
    header = {"step": STEP, "tile": TILE, "size": SIZE, "tiles": ids}
    HEADER.write_text(json.dumps(header, separators=(",", ":")))
    size = sum(p.stat().st_size for p in DIR.iterdir())
    log(f"  {len(ids)} tiles, {size / 1e6:.1f} MB")
    stamp.done()


def outputs() -> list[Path]:
    return [HEADER]
