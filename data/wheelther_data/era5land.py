"""Compile ERA5-Land daily data (see era5land_download.py) into the app's climate grids.

For each calendar month, averaged over the years:
  tmx   mean daily maximum temperature (°C)
  tmn   mean daily minimum temperature (°C)
  pre   precipitation (mm/month)
  r1    days with at least 1 mm of rain
  r5    days with at least 5 mm
  r10   days with at least 10 mm

Output per continent, replacing the CRU grid: out/<continent>/climate.bin plus
climate.json. The grid is 0.25° (the downloads are already on it). Values are
one byte each (uint8, 255 = no data), laid out [layer][month][row][col]:
  tmx, tmn   value = byte / 2 - 64            (0.5 °C steps, -64 … +63 °C)
  pre        value = (byte / 8) ** 2          (fine for dry months, up to ~1000 mm)
  r1/r5/r10  value = byte / 8                 (1/8 day steps)

Usage: uv run python -m wheelther_data.era5land [--from 2011] [--to 2025]
"""

import argparse
import json
from pathlib import Path

import numpy as np
import xarray as xr

from .continents import CONTINENTS

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "cache" / "era5land"
OUT = ROOT / "out"
NODATA = 255
LAYERS = ["tmx", "tmn", "pre", "r1", "r5", "r10"]
ENCODING = {
    "tmx": {"kind": "linear", "scale": 2, "offset": -64},
    "tmn": {"kind": "linear", "scale": 2, "offset": -64},
    "pre": {"kind": "sqrt", "scale": 8},
    "r1": {"kind": "linear", "scale": 8, "offset": 0},
    "r5": {"kind": "linear", "scale": 8, "offset": 0},
    "r10": {"kind": "linear", "scale": 8, "offset": 0},
}
SOURCE = "ERA5-Land (Copernicus Climate Change Service, ECMWF), daily data on a 0.25° grid"


def _data(path: Path) -> xr.DataArray:
    ds = xr.open_dataset(path)
    var = next(v for v in ds.data_vars if ds[v].ndim == 3)
    da = ds[var]
    tdim = next(d for d in da.dims if "time" in d)
    da = da.rename({tdim: "time"})
    if "longitude" in da.dims:
        da = da.rename({"longitude": "lon", "latitude": "lat"})
    # -180 and 180 are the same meridian; keep one.
    if float(da.lon[-1]) >= 180 and float(da.lon[0]) <= -180:
        da = da.isel(lon=slice(0, -1))
    return da.sortby("lat", ascending=False)


def accumulate(y0: int, y1: int):
    """Monthly sums over all years: returns dict of (12, lat, lon) arrays and the grid."""
    sums = {k: None for k in ("tmx", "tmn", "pre", "r1", "r5", "r10")}
    ndays = {k: np.zeros(12) for k in ("t", "p")}
    tcount = {"tmx": None, "tmn": None}
    grid = None

    def add(key, month, values):
        if sums[key] is None:
            sums[key] = np.zeros((12, *values.shape[-2:]), dtype=np.float64)
        sums[key][month] += np.nansum(values, axis=0) if values.ndim == 3 else values

    for y in range(y0, y1 + 1):
        # Rain: 00:00 of day D is the total of D-1.
        tp = _data(CACHE / f"tp00-{y}.nc")
        nxt = _data(CACHE / f"tp00-{y + 1}-01-01.nc")
        days = xr.concat([tp.isel(time=slice(1, None)), nxt], dim="time")
        days = days.assign_coords(time=days.time - np.timedelta64(1, "D"))
        mm = (days * 1000).astype("float32")  # m -> mm
        if grid is None:
            grid = (mm.lat.values, mm.lon.values)
            land = np.isfinite(mm.isel(time=0).values)
        for m in range(12):
            sel = mm.sel(time=mm.time.dt.month == m + 1).values
            if sel.size == 0:
                continue
            ndays["p"][m] += sel.shape[0]
            add("pre", m, sel)
            for t, key in ((1, "r1"), (5, "r5"), (10, "r10")):
                add(key, m, (sel >= t).astype("float32"))
        print(f"  rain {y}", flush=True)

        for stat, key in (("maximum", "tmx"), ("minimum", "tmn")):
            for m in range(12):
                f = CACHE / f"t2m-{stat}-{y}-{m + 1:02d}.nc"
                t = _data(f).values - 273.15  # K -> °C
                add(key, m, t)
                if key == "tmx":
                    ndays["t"][m] += t.shape[0]
        print(f"  temperature {y}", flush=True)

    nyears = y1 - y0 + 1
    clim = {
        "tmx": sums["tmx"] / ndays["t"][:, None, None],
        "tmn": sums["tmn"] / ndays["t"][:, None, None],
        # Monthly totals: average over the years.
        "pre": sums["pre"] / nyears,
        "r1": sums["r1"] / nyears,
        "r5": sums["r5"] / nyears,
        "r10": sums["r10"] / nyears,
    }
    for k in clim:
        clim[k][:, ~land] = np.nan
    return clim, grid


def encode(name: str, v: np.ndarray) -> np.ndarray:
    e = ENCODING[name]
    if e["kind"] == "sqrt":
        b = np.sqrt(np.clip(v, 0, None)) * e["scale"]
    else:
        b = (v - e["offset"]) * e["scale"]
    b = np.clip(np.round(b), 0, NODATA - 1)
    return np.where(np.isnan(v), NODATA, b).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="y0", type=int, default=2011)
    ap.add_argument("--to", dest="y1", type=int, default=2025)
    args = ap.parse_args()
    clim, (lats, lons) = accumulate(args.y0, args.y1)
    for c in CONTINENTS:
        x0, y0, x1, y1 = c["bbox"]
        rows = np.where((lats >= y0) & (lats <= y1))[0]
        cols = np.where((lons >= x0) & (lons <= x1))[0]
        data = np.stack([encode(k, clim[k][:, rows][:, :, cols]) for k in LAYERS])
        d = OUT / c["id"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "climate.bin").write_bytes(data.tobytes())
        header = {
            "source": SOURCE,
            "years": [args.y0, args.y1],
            "lon0": float(lons[cols[0]]),
            "lat0": float(lats[rows[0]]),
            "step": 0.25,
            "cols": int(len(cols)),
            "rows": int(len(rows)),
            "dtype": "u8",
            "vars": LAYERS,
            "encoding": ENCODING,
            "nodata": NODATA,
        }
        (d / "climate.json").write_text(json.dumps(header, separators=(",", ":")))
        print(f"  {c['id']:14} {len(cols)}x{len(rows)} cells, {data.nbytes / 1e6:.1f} MB", flush=True)


if __name__ == "__main__":
    main()
