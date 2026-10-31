"""Wind: the afternoon wind people ride in, for headwinds along a route.

- download era5land-wind (era5land_download.py): ERA5-Land's 10 m wind, east
  (u) and north (v) components, monthly means for each hour of the day.
- download era5-wind-speed: ERA5's 10 m wind speed, the same way (the mean of
  each hour's speed; ERA5-Land has no speed of its own).
- build wind: per year, each month's strongest riding hour (RIDING, in local
  solar time from the cell's longitude, so 9:00 in Lisbon and in Vladivostok
  alike): its mean speed, and its mean wind vector for the direction, into
  cache/wind/<year>.npz, one stamp per year; then per climate the average of
  its years into cache/grids/wind-<climate>.npz (`wspd`, `u10`, `v10`,
  (12, rows, cols), m/s). The pack step adds them to that climate.

Which years: the 2011–2025 climate and El Niño / La Niña use 2011–2025
(their corrections are for temperature and rain only); the last 10, 5 and
1 years use their own years.

Why the strongest hour, and why the speed separately: averaging the
components lets winds from different sides cancel, so a gusty afternoon that
blows from a new side every day averages to calm, and a mean over all riding
hours dilutes the windy afternoon with the calm morning. The speed is what a
rider feels; the mean vector of the same hour says which way it pushes, and
how steady that is (its length against the speed: 1 when it always blows
from the same side, near 0 when from every side in turn).
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
RIDING = range(9, 17)  # local solar hours compared: 9:00 … 16:00, the hours most riding is done
LAYERS = ("wspd", "u10", "v10")  # in the climate: speed, east and north components


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


def _by_hour(path: Path, name: str) -> tuple[np.ndarray, np.ndarray]:
    """A variable's monthly means per riding hour, (12, len(RIDING), rows, cols), and the file's longitudes."""
    import xarray as xr

    with xr.open_dataset(path) as ds:
        rows = ds.latitude.values >= e.SOUTH
        t = ds.valid_time.values
        month = t.astype("datetime64[M]").astype(int) % 12
        hour = t.astype("datetime64[h]").astype(int) % 24
        vals = ds[name].values[:, rows]
        byhour = np.full((12, 24, *vals.shape[1:]), np.nan, dtype=np.float32)
        byhour[month, hour] = vals
        del vals
        idx = riding_hours(ds.longitude.values)  # (k, cols)
    pick = np.broadcast_to(idx[None, :, None, :], (12, len(RIDING), *byhour.shape[2:]))
    return np.take_along_axis(byhour, pick, axis=1)


def _daytime(y: int) -> dict[str, np.ndarray]:
    """One year's strongest riding hour per month: its speed and wind vector, (12, rows, cols) each, NaN at sea."""
    speed = _by_hour(dl.wind_speed_file(y), "si10")
    strongest = np.nanargmax(np.where(np.isnan(speed), -1, speed), axis=1)[:, None]  # (12, 1, rows, cols)
    out = {"wspd": np.take_along_axis(speed, strongest, axis=1)[:, 0]}
    del speed
    for name in ("u10", "v10"):
        out[name] = np.take_along_axis(_by_hour(dl.wind_file(y), name), strongest, axis=1)[:, 0]
    out["wspd"][np.isnan(out["u10"])] = np.nan  # land only, like ERA5-Land
    return out


def extract(years: range, fresh: bool = False) -> None:
    code = code_hash(e, dl, pipeline) + hashlib.sha1((inspect.getsource(_by_hour) + inspect.getsource(_daytime) + repr(RIDING)).encode()).hexdigest()[:12]
    for y in years:
        out = year_file(y)
        stamp = Stamp(f"wind-{y}", [dl.wind_file(y), dl.wind_speed_file(y)], [out], code)
        if not fresh and stamp.up_to_date():
            continue
        if stamp.missing_inputs():
            raise SystemExit(f"Missing the wind for {y}. Run: download era5land-wind era5-wind-speed")
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
        for key in LAYERS:
            out[key] = np.mean([np.load(year_file(y))[key].astype(np.float32) for y in ys], axis=0)
        tmp = grid_file(climate).with_name(f"wind-{climate}.part.npz")
        np.savez(tmp, **out)
        tmp.replace(grid_file(climate))
        steady = np.hypot(out["u10"], out["v10"]) / out["wspd"]
        log(f"  {climate:7} {ys[0]}–{ys[-1]}: strongest riding hour, median over land {np.nanmedian(out['wspd']):.1f} m/s, steadiness {np.nanmedian(steady):.2f}")
    stamp.done()
