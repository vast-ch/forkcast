"""Wind: the prevailing wind in the hours people ride, for headwinds along a route.

- download era5land-wind (era5land_download.py): ERA5-Land's 10 m wind, east
  (u) and north (v) components, monthly means for each hour of the day.
- build wind: per year, each month's mean wind vector over RIDING local
  hours (solar time from the cell's longitude, so 9:00 in Lisbon and in
  Vladivostok alike), into cache/wind/<year>.npz, one stamp per year; then
  per climate the average of its years into cache/grids/wind-<climate>.npz
  (`u10`, `v10`, (12, rows, cols), m/s). The pack step adds them to that
  climate.

Which years: the 2011–2025 climate and El Niño / La Niña use 2011–2025
(their corrections are for temperature and rain only); the last 10, 5 and
1 years use their own years.

Why a mean vector, not a mean speed: the monthly means average the
components, so a wind that blows east half the days and west the other half
averages to calm. That is exactly right for what the app needs: the average
headwind along a stretch is the mean wind vector against the direction
ridden, whatever the wind does from day to day. It understates how windy a
place feels, so the app speaks of the prevailing wind and the average
headwind, never of how strong the wind is.
"""

from __future__ import annotations

import hashlib
import inspect
import sys
from pathlib import Path

import numpy as np

from . import era5land as e
from . import era5land_download as dl
from . import pipeline, variants
from .pipeline import CACHE, Stamp, code_hash, log

DIR = CACHE / "wind"
RIDING = range(9, 17)  # local solar hours averaged: 9:00 … 16:00, the hours most riding is done
COMPONENTS = {"u10": "u10", "v10": "v10"}  # in the download → in the climate


def year_file(y: int) -> Path:
    return DIR / f"{y}.npz"


def grid_file(climate: str) -> Path:
    return e.GRIDS / f"wind-{climate}.npz"


def climate_years(app: tuple[int, int]) -> dict[str, list[int]]:
    """Each climate's years (see the module's docstring)."""
    period = list(range(app[0], app[1] + 1))
    windows = variants.windows(app)
    return {c: windows.get(c, period) for c in ["last15", *variants.VARIANTS]}


def riding_hours(lon: np.ndarray) -> np.ndarray:
    """(len(RIDING), cols) the UTC hour of each riding hour, per column's longitude."""
    local = np.array(RIDING)[:, None]
    return np.round(local - lon[None, :] / 15).astype(int) % 24


def _daytime(y: int) -> dict[str, np.ndarray]:
    """One year's monthly mean wind over the riding hours, (12, rows, cols) per component, NaN at sea."""
    import xarray as xr

    out = {}
    with xr.open_dataset(dl.wind_file(y)) as ds:
        lat = ds.latitude.values
        rows = lat >= e.SOUTH
        t = ds.valid_time.values
        month = t.astype("datetime64[M]").astype(int) % 12
        hour = t.astype("datetime64[h]").astype(int) % 24
        idx = riding_hours(ds.longitude.values)  # (k, cols)
        for name, key in COMPONENTS.items():
            vals = ds[name].values[:, rows]
            byhour = np.full((12, 24, *vals.shape[1:]), np.nan, dtype=np.float32)
            byhour[month, hour] = vals
            del vals
            pick = np.broadcast_to(idx[None, :, None, :], (12, len(RIDING), byhour.shape[2], byhour.shape[3]))
            out[key] = np.take_along_axis(byhour, pick, axis=1).mean(axis=1)
    return out


def extract(years: range, fresh: bool = False) -> None:
    code = code_hash(e, dl, pipeline) + hashlib.sha1(inspect.getsource(_daytime).encode() + repr(RIDING).encode()).hexdigest()[:12]
    for y in years:
        out = year_file(y)
        stamp = Stamp(f"wind-{y}", [dl.wind_file(y)], [out], code)
        if not fresh and stamp.up_to_date():
            continue
        if stamp.missing_inputs():
            raise SystemExit(f"Missing the wind for {y}. Run: download era5land-wind")
        f = _daytime(y)
        out.parent.mkdir(parents=True, exist_ok=True)
        tmp = out.with_name(out.stem + ".part.npz")
        np.savez(tmp, **{k: v.astype(np.float16) for k, v in f.items()})
        tmp.replace(out)
        stamp.done()
        log(f"  wind {y}")


def build(app: tuple[int, int], fresh: bool = False) -> None:
    years = range(app[0], app[1] + 1)
    extract(years, fresh)
    per = climate_years(app)
    outputs = [grid_file(c) for c in per]
    stamp = Stamp("wind", [year_file(y) for y in years], outputs, code_hash(sys.modules[__name__], pipeline), {"years": list(app)})
    if not fresh and stamp.up_to_date():
        log("  wind is up to date")
        return
    for climate, ys in per.items():
        out = {}
        for key in COMPONENTS.values():
            out[key] = np.mean([np.load(year_file(y))[key].astype(np.float32) for y in ys], axis=0)
        tmp = grid_file(climate).with_name(f"wind-{climate}.part.npz")
        np.savez(tmp, **out)
        tmp.replace(grid_file(climate))
        speed = np.hypot(out["u10"], out["v10"])
        log(f"  {climate:7} {ys[0]}–{ys[-1]}: prevailing wind, median over land {np.nanmedian(speed):.1f} m/s")
    stamp.done()
