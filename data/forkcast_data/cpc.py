"""Daily highs and lows from NOAA's CPC Global Daily Temperature (station-based, 0.5°).

ERA5-Land gives the average day of each month; it can't say how much single
days vary around it. CPC gridded the world's weather stations' daily maximum
and minimum since 1979, so from it we measure that spread: per place and time
of year, how far a day's high and a night's low typically fall from their
average. The averages themselves stay ERA5-Land's (finer grid, calibrated
with CRU).

- download cpc: tmax.<year>.nc and tmin.<year>.nc from NOAA PSL, one file each
  per year (about 80 MB), into cache/cpc/.
- build spread: per 0.5° cell, each day's departure from the cell's seasonal
  curve (the yearly mean and three yearly waves, fitted to all its days),
  then per month the standard deviation of those departures over all the
  years' days in it. Interpolated onto the climate's 0.25° grid (land cells
  beyond CPC's coast take their nearest neighbours') into
  cache/grids/spread.npz: `tmxsd`, `tmnsd`, (12, rows, cols), °C. The pack
  step adds them to every climate.

Data: CPC Global Unified Temperature, NOAA PSL, Boulder, Colorado, USA,
https://psl.noaa.gov (public domain).
"""

from __future__ import annotations

import calendar
import json
import sys
import warnings
from pathlib import Path

import numpy as np

from . import era5land as e
from . import pipeline
from .pipeline import CACHE, Stamp, code_hash, ensure, http_get, log

DIR = CACHE / "cpc"
SERVER = "https://downloads.psl.noaa.gov/Datasets/cpc_global_temp/"
KINDS = ("tmax", "tmin")
LAYERS = {"tmax": "tmxsd", "tmin": "tmnsd"}  # what each becomes in the climate
OUT = e.GRIDS / "spread.npz"
HARMONICS = 3  # of the seasonal curve the departures are measured from
BAND = 20  # rows of the 0.5° grid read at a time (~320 MB for 15 years)


def file(kind: str, year: int) -> Path:
    return DIR / f"{kind}.{year}.nc"


def files(years: range) -> list[Path]:
    return [file(k, y) for y in years for k in KINDS]


def _check(kind: str, year: int):
    def validate(path: Path) -> None:
        import xarray as xr

        with xr.open_dataset(path) as ds:
            da = ds[kind]
            n = 366 if calendar.isleap(year) else 365
            if da.sizes["time"] != n:
                raise ValueError(f"{da.sizes['time']} days, expected {n}")
            if (da.sizes["lat"], da.sizes["lon"]) != (360, 720):
                raise ValueError("not the global 0.5° grid")
            if not (da.isel(time=-1).values == da.isel(time=-1).values).any():
                raise ValueError("last day has no data")

    return validate


def download(years: range, fresh: bool = False) -> None:
    for y in years:
        for k in KINDS:
            log("  " + ensure(file(k, y), lambda to, k=k, y=y: http_get(f"{SERVER}{k}.{y}.nc", to), _check(k, y), fresh))


# --- Spread --------------------------------------------------------------------


def _seasons(days: np.ndarray) -> np.ndarray:
    """(days,) dates → (days, 1 + 2 × HARMONICS) the seasonal curve's terms."""
    year = days.astype("datetime64[Y]")
    doy = (days - year).astype(int)
    length = ((year + 1).astype("datetime64[D]") - year.astype("datetime64[D]")).astype(int)
    phase = (doy + 0.5) / length
    cols = [np.ones_like(phase)]
    for k in range(1, HARMONICS + 1):
        cols += [np.cos(2 * np.pi * k * phase), np.sin(2 * np.pi * k * phase)]
    return np.stack(cols, axis=1)


def monthly_spread(x: np.ndarray, days: np.ndarray) -> np.ndarray:
    """Daily values (days, …) → (12, …) the standard deviation of each month's
    departures from the seasonal curve fitted to all the days. NaN days are
    left out (filled with the curve while fitting it)."""
    X = _seasons(days)
    flat = x.reshape(len(days), -1)
    months = days.astype("datetime64[M]").astype(int) % 12
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)  # cells without data (sea)
        filled = np.where(np.isnan(flat), np.nanmean(flat, axis=0), flat)
        beta, *_ = np.linalg.lstsq(X, np.nan_to_num(filled), rcond=None)
        res = flat - X @ beta
        out = np.stack([np.nanstd(res[months == m], axis=0) for m in range(12)])
    return out.reshape(12, *x.shape[1:]).astype(np.float32)


def _fill(a: np.ndarray, steps: int = 6) -> np.ndarray:
    """NaN cells take the mean of their neighbours that have a value, `steps` times (spreads land data out to the coasts)."""
    a = a.copy()
    for _ in range(steps):
        p = np.pad(a, ((0, 0), (1, 1), (0, 0)), constant_values=np.nan)
        near = np.stack([np.roll(p, (dr, dc), axis=(1, 2))[:, 1:-1] for dr in (-1, 0, 1) for dc in (-1, 0, 1) if dr or dc])
        with np.errstate(invalid="ignore"), warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            mean = np.nanmean(near, axis=0)
        a = np.where(np.isnan(a), mean, a)
    return a


def regrid(a: np.ndarray, lat: np.ndarray, lon: np.ndarray, to_lat: np.ndarray, to_lon: np.ndarray) -> np.ndarray:
    """(…, lat, lon) on CPC's grid (lat descending, lon 0–360) → bilinear on the climate's cell centres."""
    lon = np.where(lon > 180, lon - 360, lon)
    order = np.argsort(lon)
    lon, a = lon[order], a[..., order]
    lon = np.concatenate([lon[-1:] - 360, lon, lon[:1] + 360])  # wrap round
    a = np.concatenate([a[..., -1:], a, a[..., :1]], axis=-1)
    fr = np.clip((lat[0] - to_lat) / (lat[0] - lat[1]), 0, len(lat) - 1.0001)
    fc = (to_lon - lon[0]) / (lon[1] - lon[0])
    r0, c0 = np.floor(fr).astype(int), np.floor(fc).astype(int)
    wr, wc = (fr - r0)[:, None], (fc - c0)[None, :]
    g = lambda dr, dc: a[..., (r0 + dr)[:, None], (c0 + dc)[None, :]]  # noqa: E731
    return (g(0, 0) * (1 - wr) * (1 - wc) + g(0, 1) * (1 - wr) * wc + g(1, 0) * wr * (1 - wc) + g(1, 1) * wr * wc).astype(np.float32)


def build(years: range, fresh: bool = False) -> None:
    import xarray as xr

    header = e.grid_file("json")
    stamp = Stamp("spread", [*files(years), header], [OUT], code_hash(sys.modules[__name__], e, pipeline), {"years": [years[0], years[-1]]})
    if not fresh and stamp.up_to_date():
        log("  spread is up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing {missing[0].name}. Run: download cpc, build climate")
    h = json.loads(header.read_text())
    to_lat = h["lat0"] - np.arange(h["rows"]) * h["step"]
    to_lon = h["lon0"] + np.arange(h["cols"]) * h["step"]
    out = {}
    for kind in KINDS:
        sets = [xr.open_dataset(file(kind, y)) for y in years]
        days = np.concatenate([d.time.values.astype("datetime64[D]") for d in sets])
        lat, lon = sets[0].lat.values, sets[0].lon.values
        sd = np.full((12, len(lat), len(lon)), np.nan, dtype=np.float32)
        for r in range(0, len(lat), BAND):
            x = np.concatenate([d[kind].isel(lat=slice(r, r + BAND)).values for d in sets])
            sd[:, r : r + BAND] = monthly_spread(x, days)
        for d in sets:
            d.close()
        out[LAYERS[kind]] = regrid(_fill(sd), lat, lon, to_lat, to_lon)
        log(f"  {kind}: median spread {np.nanmedian(sd):.1f} °C")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_name("spread.part.npz")
    np.savez(tmp, **out)
    tmp.replace(OUT)
    stamp.done()
