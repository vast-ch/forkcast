"""The map's relief shading: terrain heights at 0.1° in 10° tiles.

The climate tiles carry each 0.25° cell's mean height (for the altitude
correction), and the relief was once shaded from those: valleys and ranges
blurred into 25 km blobs. This step publishes ERA5-Land's own terrain (the
`orography` download, 0.1°, about 11 km) for the shading alone, in the same
10° squares as the climate, so the app fetches a square's relief only with
its climate tile and only while the Relief layer is on.

Output: out/relief.json (step, tile, size, which tiles exist) and
out/relief/<lat>_<lon>.bin for each 10° tile the climate has (by its
south-west corner, like the climate's): SIZE × SIZE heights from the north-west corner,
rows north to south, sharing their edges with the neighbours, each a
little-endian int16 in metres (about 20 KB a tile). The sea is about 0:
flat, so it shades as nothing (and the app draws only on the climate's land).

Usage: uv run python -m forkcast_data build relief [--fresh]
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

import numpy as np

from . import era5land_download as dl
from . import pack, pipeline
from .pack import TILE
from .pipeline import OUT, Stamp, code_hash, log

DIR = OUT / "relief"
HEADER = OUT / "relief.json"
STEP = 0.1
SIZE = round(TILE / STEP) + 1


def heights() -> np.ndarray:
    """The world's terrain (m) at 0.1°: rows from 90° N to 90° S, columns from 180° W eastwards."""
    import xarray as xr

    with xr.open_dataset(dl.orography_file()) as ds:
        z = ds["z"].squeeze(drop=True)
        z = z.rename({d: {"latitude": "lat", "longitude": "lon"}.get(d, d) for d in z.dims})
        h = (z / 9.80665).values
        lon0 = float(z.lon.values[0])
    # The file starts at 0° E; roll it to start at 180° W, as the tiles count.
    return np.roll(h, round((lon0 + 180) / STEP), axis=1)


def cut(world: np.ndarray, lat: int, lon: int) -> np.ndarray:
    """A tile's SIZE × SIZE heights, from its north-west corner; columns wrap round at 180°, rows past a pole are sea."""
    r = round((90 - (lat + TILE)) / STEP) + np.arange(SIZE)
    c = (round((lon + 180) / STEP) + np.arange(SIZE)) % world.shape[1]
    out = np.zeros((SIZE, SIZE))
    ok = (r >= 0) & (r < world.shape[0])
    out[ok] = world[r[ok][:, None], c[None, :]]
    return out


def encode(tile: np.ndarray) -> bytes:
    return np.clip(np.round(tile), -32768, 32767).astype("<i2").tobytes()


def build(fresh: bool = False) -> None:
    climate = pack.header_file("last15")
    stamp = Stamp("relief", [dl.orography_file(), climate], [HEADER], code_hash(sys.modules[__name__], pack, pipeline))
    if not fresh and stamp.up_to_date():
        log("  relief is up to date")
        return
    if stamp.missing_inputs():
        raise SystemExit("Missing the terrain or the climate. Run: download orography, build pack")
    world = heights()
    if DIR.exists():
        shutil.rmtree(DIR)
    DIR.mkdir(parents=True)
    # The same squares as the climate: the app asks for a square's relief with its climate tile.
    ids = sorted(json.loads(climate.read_text())["tiles"])
    for tid in ids:
        lat, lon = map(int, tid.split("_"))
        (DIR / f"{tid}.bin").write_bytes(encode(cut(world, lat, lon)))
    header = {"step": STEP, "tile": TILE, "size": SIZE, "tiles": ids}
    HEADER.write_text(json.dumps(header, separators=(",", ":")))
    size = sum(p.stat().st_size for p in DIR.iterdir())
    log(f"  {len(ids)} tiles, {size / 1e6:.1f} MB")
    stamp.done()


def outputs() -> list[Path]:
    return [HEADER]
