"""Build the app's climate grids from ERA5-Land, calibrated with CRU.

For each calendar month, averaged over the years (2011–2025 by default):
  tmx   mean daily maximum temperature (°C)
  tmn   mean daily minimum temperature (°C)
  pre   precipitation (mm/month)
  r1    days with at least 1 mm of rain
  r5    days with at least 5 mm
  r10   days with at least 10 mm

Rain comes straight from ERA5-Land's daily totals, so r1/r5/r10 are counted,
not estimated.

Highs and lows: ERA5-Land's monthly means for each hour of the day give the
average day's temperature curve; its warmest and coldest hour are close to,
but less extreme than, the average daily maximum and minimum (on any one day
the extremes fall at different hours). That gap is closed with CRU, whose
tmx/tmn are station-based means of the real daily extremes:

    offset  = CRU_tmx − (ERA5-Land warmest hour, averaged onto CRU's 0.5° cell)
    tmx     = ERA5-Land warmest hour (0.25°) + offset (smoothed, interpolated to 0.25°)

and the same for tmn with the coldest hour. ERA5-Land keeps the fine detail
(coasts, valleys), CRU sets the level. Where CRU has no cell (small islands,
coast) the offset is taken from the nearest cells that have one.

Altitude: each cell's mean height (from ERA5-Land's own terrain, averaged
from 0.1° to the 0.25° cells) is stored too. The app shifts temperatures by a seasonal lapse rate (4.4–6.8 °C per 1,000 m) between a route point and its cell, so a valley town or a pass gets its own temperature, not the cell's.

Output per continent: cache/grids/<continent>/climate.bin and climate.json,
which the pack step publishes to out/ as seasonal curves (pack.py). The grid is
0.25°. Values are one byte each (uint8, 255 = no data), laid out
[layer][month][row][col], followed by the static layers [row][col]:
  tmx, tmn   value = byte / 2 - 64            (0.5 °C steps, -64 … +63 °C)
  pre        value = (byte / 8) ** 2          (fine for dry months, up to ~1000 mm)
  r1/r5/r10  value = byte / 8                 (1/8 day steps)
  elev       value = byte × 40 m              (static; 0 … 10,160 m, below sea level as 0)

Usage: uv run python -m forkcast_data build climate [--fresh]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import warnings

import numpy as np

from . import continents, cru, era5land_download as dl, pipeline
from .continents import CONTINENTS
from .pipeline import CACHE, Stamp, code_hash, log

NODATA = 255
LAYERS = ["tmx", "tmn", "pre", "r1", "r5", "r10"]
ENCODING = {
    "tmx": {"kind": "linear", "scale": 2, "offset": -64},
    "tmn": {"kind": "linear", "scale": 2, "offset": -64},
    "pre": {"kind": "sqrt", "scale": 8},
    "r1": {"kind": "linear", "scale": 8, "offset": 0},
    "r5": {"kind": "linear", "scale": 8, "offset": 0},
    "r10": {"kind": "linear", "scale": 8, "offset": 0},
    "elev": {"kind": "linear", "scale": 0.025, "offset": 0},
}
STATIC = ["elev"]
SOURCE = "ERA5-Land (Copernicus Climate Change Service), highs and lows calibrated with CRU TS 4.10"


def _open(path: Path):
    """The file's one data variable as (time, lat, lon), north first, -180 dropped if 180 present."""
    import xarray as xr

    ds = xr.open_dataset(path)
    var = next(v for v in ds.data_vars if ds[v].ndim >= 3)
    da = ds[var]
    da = da.rename({d: "time" for d in da.dims if "time" in d})
    if "longitude" in da.dims:
        da = da.rename({"longitude": "lon", "latitude": "lat"})
    if float(da.lon[-1]) >= 180 and float(da.lon[0]) <= -180:
        da = da.isel(lon=slice(0, -1))
    return da.sortby("lat", ascending=False)


def _next_january(y: int) -> Path:
    """The file holding 1 January of year y+1 (31 December's total)."""
    full = dl.rain_file(y + 1)
    return full if full.exists() else dl.rain_last_day(y + 1)


def rain(y0: int, y1: int):
    """Monthly rain totals and rainy-day counts, averaged over the years."""
    sums = None
    for y in range(y0, y1 + 1):
        tp = _open(dl.rain_file(y))
        nxt = _open(_next_january(y)).isel(time=slice(0, 1))
        # 00:00 of day D is the total of D-1: drop 1 January (it is 31 December
        # of the year before) and add the next year's 1 January.
        mm = np.concatenate([tp.values[1:], nxt.values], axis=0) * 1000.0
        dates = np.concatenate([tp.time.values[1:], nxt.time.values]) - np.timedelta64(1, "D")
        months = dates.astype("datetime64[M]").astype(int) % 12
        if sums is None:
            shape = mm.shape[1:]
            sums = {k: np.zeros((12, *shape), dtype=np.float64) for k in ("pre", "r1", "r5", "r10")}
            land = np.isfinite(mm[0])
            grid = (tp.lat.values, tp.lon.values)
        for m in range(12):
            sel = mm[months == m]
            sums["pre"][m] += np.nansum(sel, axis=0)
            for t, key in ((1, "r1"), (5, "r5"), (10, "r10")):
                sums[key][m] += (sel >= t).sum(axis=0)
        log(f"  rain {y}")
    n = y1 - y0 + 1
    out = {k: v / n for k, v in sums.items()}
    for v in out.values():
        v[:, ~land] = np.nan
    return out, grid, land


def hourly_extremes(y0: int, y1: int):
    """Warmest and coldest hour of each month's average day, °C."""
    total = None
    for y in range(y0, y1 + 1):
        t = _open(dl.temperature_file(y))
        months = t.time.values.astype("datetime64[M]").astype(int) % 12
        hours = (t.time.values.astype("datetime64[h]").astype(int)) % 24
        vals = t.values.astype(np.float32) - np.float32(273.15)
        if total is None:
            total = np.zeros((12, 24, *vals.shape[1:]), dtype=np.float32)
        for i in range(vals.shape[0]):
            total[months[i], hours[i]] += vals[i]
        log(f"  temperature {y}")
    mean = total / np.float32(y1 - y0 + 1)
    return np.nanmax(mean, axis=1), np.nanmin(mean, axis=1)


# Means over cells with no land at all are expected (open sea); they stay NaN.
warnings.filterwarnings("ignore", "Mean of empty slice", RuntimeWarning)
warnings.filterwarnings("ignore", "All-NaN slice encountered", RuntimeWarning)


def _fill_nearest(a: np.ndarray, passes: int = 12) -> np.ndarray:
    """Fill NaNs from the mean of neighbouring values, growing outwards."""
    a = a.copy()
    for _ in range(passes):
        nan = np.isnan(a)
        if not nan.any():
            break
        p = np.pad(a, 1, constant_values=np.nan)
        stack = np.stack([p[1 + dy : p.shape[0] - 1 + dy, 1 + dx : p.shape[1] - 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
        with np.errstate(all="ignore"):
            near = np.nanmean(stack, axis=0)
        a[nan] = near[nan]
    return a


def _smooth(a: np.ndarray) -> np.ndarray:
    p = np.pad(a, 1, mode="edge")
    stack = np.stack([p[1 + dy : p.shape[0] - 1 + dy, 1 + dx : p.shape[1] - 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
    with np.errstate(all="ignore"):
        return np.nanmean(stack, axis=0)


def calibrate(fine: np.ndarray, lats: np.ndarray, lons: np.ndarray, cru_da, name: str) -> np.ndarray:
    """Shift a (12, lat, lon) 0.25° field so its 0.5° cell means match CRU."""
    clat = cru_da.lat.values  # north first
    clon = cru_da.lon.values
    out = np.empty_like(fine)
    # Index of the 0.25° point at each CRU cell centre (centres sit on the 0.25° grid).
    iy = np.round((lats[0] - clat) / 0.25).astype(int)
    ix = np.round((clon - lons[0]) / 0.25).astype(int)
    ok_y = (iy >= 1) & (iy < len(lats) - 1)
    ok_x = (ix >= 1) & (ix < len(lons) - 1)
    medians = []
    for m in range(12):
        f = fine[m]
        # Mean of the 3 × 3 fine points covering each CRU cell.
        coarse = np.full((len(clat), len(clon)), np.nan, dtype=np.float32)
        yy, xx = np.meshgrid(iy[ok_y], ix[ok_x], indexing="ij")
        acc = np.stack([f[yy + dy, xx + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)])
        with np.errstate(all="ignore"):
            coarse[np.ix_(ok_y, ok_x)] = np.nanmean(acc, axis=0)
        off = cru_da.sel(month=m + 1).values - coarse
        medians.append(float(np.nanmedian(off)))
        off = _smooth(_fill_nearest(off))
        off = np.where(np.isnan(off), medians[-1], off)
        # Bilinear interpolation of the offset onto the 0.25° grid.
        fy = np.clip((clat[0] - lats) / 0.5, 0, len(clat) - 1)
        fx = np.clip((lons - clon[0]) / 0.5, 0, len(clon) - 1)
        y0 = np.floor(fy).astype(int)
        x0 = np.floor(fx).astype(int)
        y1 = np.minimum(y0 + 1, len(clat) - 1)
        x1 = np.minimum(x0 + 1, len(clon) - 1)
        ty = (fy - y0)[:, None]
        tx = (fx - x0)[None, :]
        o = (
            off[np.ix_(y0, x0)] * (1 - ty) * (1 - tx)
            + off[np.ix_(y0, x1)] * (1 - ty) * tx
            + off[np.ix_(y1, x0)] * ty * (1 - tx)
            + off[np.ix_(y1, x1)] * ty * tx
        )
        out[m] = f + o
    log(f"  {name} calibration, median offset by month (°C): " + " ".join(f"{x:+.1f}" for x in medians))
    return out


def cell_elevation(lats: np.ndarray, lons: np.ndarray) -> np.ndarray:
    """Mean terrain height (m) of each 0.25° cell, from ERA5-Land's 0.1° orography."""
    import xarray as xr

    with xr.open_dataset(dl.orography_file()) as ds:
        z = ds["z"].squeeze(drop=True)
        z = z.rename({d: {"latitude": "lat", "longitude": "lon"}.get(d, d) for d in z.dims})
        h = (z / 9.80665).values.astype(np.float64)
        zlat = z.lat.values
        zlon = ((z.lon.values + 180) % 360) - 180
    # Each 0.1° point goes to the nearest 0.25° cell centre.
    iy = np.round((lats[0] - zlat) / 0.25).astype(int)
    ix = np.round((zlon - lons[0]) / 0.25).astype(int)
    oky = (iy >= 0) & (iy < len(lats))
    okx = (ix >= 0) & (ix < len(lons))
    total = np.zeros((len(lats), len(lons)))
    count = np.zeros((len(lats), len(lons)))
    yy, xx = np.meshgrid(iy[oky], ix[okx], indexing="ij")
    np.add.at(total, (yy, xx), h[np.ix_(oky, okx)])
    np.add.at(count, (yy, xx), 1)
    with np.errstate(invalid="ignore"):
        return total / count


def encode(name: str, v: np.ndarray) -> np.ndarray:
    e = ENCODING[name]
    if e["kind"] == "sqrt":
        b = np.sqrt(np.clip(v, 0, None)) * e["scale"]
    else:
        b = (v - e["offset"]) * e["scale"]
    b = np.clip(np.round(b), 0, NODATA - 1)
    return np.where(np.isnan(v), NODATA, b).astype(np.uint8)


GRIDS = CACHE / "grids"


def grid_file(cid: str, ext: str) -> Path:
    return GRIDS / cid / f"climate.{ext}"


def outputs() -> list[Path]:
    return [grid_file(c["id"], x) for c in CONTINENTS for x in ("bin", "json")]


def inputs(y0: int, y1: int) -> list[Path]:
    files = [dl.rain_file(y) for y in range(y0, y1 + 1)] + [_next_january(y1)]
    files += [dl.temperature_file(y) for y in range(y0, y1 + 1)]
    return files + [cru.climatology_file(y0, y1), dl.orography_file()]


def build(y0: int, y1: int, fresh: bool = False) -> None:
    import xarray as xr

    code = code_hash(sys.modules[__name__], dl, cru, continents, pipeline)
    stamp = Stamp("climate", inputs(y0, y1), outputs(), code, {"years": [y0, y1]})
    if not fresh and stamp.up_to_date():
        log("  climate grids are up to date")
        return
    if missing := stamp.missing_inputs():
        raise SystemExit(
            f"Missing climate inputs ({missing[0].name}, …). Run: download era5land-rain, "
            "download era5land-temperature, download orography, download cru, build cru"
        )
    clim, (lats, lons), land = rain(y0, y1)
    tmax, tmin = hourly_extremes(y0, y1)
    with xr.open_dataset(cru.climatology_file(y0, y1)) as c:
        clim["tmx"] = calibrate(tmax, lats, lons, c["tmx"].load(), "highs")
        clim["tmn"] = calibrate(tmin, lats, lons, c["tmn"].load(), "lows")
    for k in ("tmx", "tmn"):
        clim[k][:, ~land] = np.nan
    elev = np.clip(cell_elevation(lats, lons), 0, None)
    for c in CONTINENTS:
        x0, ya, x1, yb = c["bbox"]
        rows = np.where((lats >= ya) & (lats <= yb))[0]
        cols = np.where((lons >= x0) & (lons <= x1))[0]
        data = np.stack([encode(k, clim[k][:, rows][:, :, cols]) for k in LAYERS])
        static = np.stack([encode("elev", np.where(land, elev, np.nan)[rows][:, cols])])
        grid_file(c["id"], "bin").parent.mkdir(parents=True, exist_ok=True)
        grid_file(c["id"], "bin").write_bytes(data.tobytes() + static.tobytes())
        header = {
            "source": SOURCE,
            "years": [y0, y1],
            "lon0": float(lons[cols[0]]),
            "lat0": float(lats[rows[0]]),
            "step": 0.25,
            "cols": int(len(cols)),
            "rows": int(len(rows)),
            "dtype": "u8",
            "vars": LAYERS,
            "static": STATIC,
            "encoding": ENCODING,
            "nodata": NODATA,
        }
        grid_file(c["id"], "json").write_text(json.dumps(header, separators=(",", ":")))
        log(f"  {c['id']:14} {len(cols)}x{len(rows)} cells, {(data.nbytes + static.nbytes) / 1e6:.1f} MB")
    stamp.done()
