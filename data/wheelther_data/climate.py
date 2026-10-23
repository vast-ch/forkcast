"""Build out/climate.json from CRU TS monthly grids.

Averages each calendar month over a range of years for:
  tmx  mean daily maximum temperature (°C)
  tmn  mean daily minimum temperature (°C)
  pre  precipitation (mm/month)
  wet  wet days (days/month with >= 0.1 mm)

Usage:
  uv run python -m wheelther_data.climate <dir with cru_ts*.dat.nc.gz> [--from 2011] [--to 2025]
"""

import argparse
import gzip
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
import xarray as xr

# Europe plus the Maghreb and Anatolia, on CRU's 0.5° grid.
LON_MIN, LON_MAX = -25.0, 45.0
LAT_MIN, LAT_MAX = 27.0, 72.0
VARS = {"tmx": 10, "tmn": 10, "pre": 1, "wet": 10}  # stored as int(value * scale)


def open_var(src: Path, var: str, tmp: Path) -> xr.DataArray:
    parts = []
    for gz in sorted(src.glob(f"cru_ts*.{var}.dat.nc.gz")):
        nc = tmp / gz.name.removesuffix(".gz")
        if not nc.exists():
            with gzip.open(gz, "rb") as fi, open(nc, "wb") as fo:
                shutil.copyfileobj(fi, fo)
        parts.append(xr.open_dataset(nc)[var])
    if not parts:
        raise SystemExit(f"No files for {var} in {src}")
    return xr.concat(parts, dim="time").sortby("time")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("--from", dest="y0", type=int, default=2011)
    ap.add_argument("--to", dest="y1", type=int, default=2025)
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "out/climate.json")
    args = ap.parse_args()

    out = {
        "source": "CRU TS 4.10, University of East Anglia",
        "years": [args.y0, args.y1],
        "lon0": LON_MIN + 0.25,
        "lat0": LAT_MAX - 0.25,  # first row is the northernmost
        "step": 0.5,
        "scale": VARS,
        "nodata": None,
    }
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for var, scale in VARS.items():
            da = open_var(args.src, var, tmp)
            da = da.sel(time=slice(f"{args.y0}-01-01", f"{args.y1}-12-31"))
            da = da.sel(lon=slice(LON_MIN, LON_MAX), lat=slice(LAT_MIN, LAT_MAX))
            if var == "wet":
                # CRU stores wet days as a timedelta in some releases.
                if np.issubdtype(da.dtype, np.timedelta64):
                    da = da / np.timedelta64(1, "D")
            clim = da.groupby("time.month").mean("time", skipna=True)
            clim = clim.sortby("lat", ascending=False)
            out["cols"] = int(clim.sizes["lon"])
            out["rows"] = int(clim.sizes["lat"])
            months = []
            for m in range(1, 13):
                a = clim.sel(month=m).values
                flat = [None if np.isnan(v) else int(round(float(v) * scale)) for v in a.ravel()]
                months.append(flat)
            out[var] = months
            print(var, clim.sizes, f"{args.y0}-{args.y1}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, separators=(",", ":")))
    print("wrote", args.out, f"{args.out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
