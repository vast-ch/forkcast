"""Build out/<continent>/climate.bin (+ climate.json header) from CRU TS monthly grids.

Averages each calendar month over a range of years for:
  tmx  mean daily maximum temperature (°C)
  tmn  mean daily minimum temperature (°C)
  pre  precipitation (mm/month)
  wet  wet days (days/month with >= 0.1 mm)

climate.bin is little-endian int16, laid out [variable][month][row][col] with
variables in the order above, rows from north to south. Each value is
round(value * scale[variable]); -32768 means no data (sea).

Usage:
  uv run python -m forkcast_data.climate <dir with cru_ts*.dat.nc.gz> [--from 2011] [--to 2025]
"""

import argparse
import gzip
import json
import shutil
import tempfile
from pathlib import Path

import numpy as np
import xarray as xr

from .continents import CONTINENTS

VARS = {"tmx": 10, "tmn": 10, "pre": 1, "wet": 10}  # stored as int(value * scale)
NODATA = -32768
SOURCE = "CRU TS 4.10, Climatic Research Unit, University of East Anglia"


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
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "out")
    args = ap.parse_args()

    clims = {}
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for var in VARS:
            da = open_var(args.src, var, tmp).sel(time=slice(f"{args.y0}-01-01", f"{args.y1}-12-31"))
            if np.issubdtype(da.dtype, np.timedelta64):  # CRU stores wet days as a timedelta
                da = da / np.timedelta64(1, "D")
            clims[var] = da.groupby("time.month").mean("time", skipna=True).sortby("lat", ascending=False).load()
            print("averaged", var, f"{args.y0}-{args.y1}", flush=True)

    for c in CONTINENTS:
        lon0, lat0, lon1, lat1 = c["bbox"]
        layers = []
        for var, scale in VARS.items():
            sub = clims[var].sel(lon=slice(lon0, lon1), lat=slice(lat1, lat0))
            vals = sub.transpose("month", "lat", "lon").values
            q = np.where(np.isnan(vals), NODATA, np.round(vals * scale)).astype("<i2")
            layers.append(q)
            rows, cols = sub.sizes["lat"], sub.sizes["lon"]
            lons, lats = sub.lon.values, sub.lat.values
        data = np.stack(layers)  # var, month, row, col
        d = args.out / c["id"]
        d.mkdir(parents=True, exist_ok=True)
        (d / "climate.bin").write_bytes(data.tobytes())
        header = {
            "source": SOURCE,
            "years": [args.y0, args.y1],
            "lon0": float(lons[0]),
            "lat0": float(lats[0]),
            "step": 0.5,
            "cols": int(cols),
            "rows": int(rows),
            "vars": list(VARS),
            "scale": VARS,
            "nodata": NODATA,
        }
        (d / "climate.json").write_text(json.dumps(header, separators=(",", ":")))
        land = int((data[0, 0] != NODATA).sum())
        print(f"  {c['id']:14} {cols}x{rows} cells, {land} on land, {data.nbytes / 1e6:.1f} MB", flush=True)


if __name__ == "__main__":
    main()
