"""CRU TS 4.10: download, and average into a monthly climatology.

CRU TS (Climatic Research Unit, University of East Anglia) is gridded from
weather-station records at 0.5°. Forkcast uses it to calibrate ERA5-Land's
daily highs and lows (see era5land.py): its tmx/tmn are true monthly means of
daily maximum and minimum temperature, measured by stations.

- download: the monthly files for tmx, tmn, pre and wet for 2011–2020 and
  2021–2025 into cache/cru/ (about 215 MB). Each is checked by decompressing it
  in full once.
- build: cache/cru/climatology-<from>-<to>.nc, each calendar month averaged
  over the years.

Usage: uv run python -m forkcast_data download cru | build cru [--fresh]
"""

from __future__ import annotations

import gzip
import sys
import shutil
import tempfile
from pathlib import Path

from . import pipeline
from .pipeline import CACHE, Stamp, code_hash, ensure, http_get, log

VERSION = "4.10"
BASE = f"https://crudata.uea.ac.uk/cru/data/hrg/cru_ts_{VERSION}/cruts.2604091129.v{VERSION}"
PERIODS = ["2011.2020", "2021.2025"]
VARS = ["tmx", "tmn", "pre", "wet"]
DIR = CACHE / "cru"


def files() -> list[Path]:
    return [DIR / f"cru_ts{VERSION}.{p}.{v}.dat.nc.gz" for v in VARS for p in PERIODS]


def climatology_file(y0: int, y1: int) -> Path:
    return DIR / f"climatology-{y0}-{y1}.nc"


def _validate_gz(path: Path) -> None:
    with gzip.open(path, "rb") as f:
        while f.read(1 << 22):
            pass


def download(fresh: bool = False) -> None:
    for path in files():
        var = path.name.split(".")[-4]
        url = f"{BASE}/{var}/{path.name}"
        log("  " + ensure(path, lambda to, url=url: http_get(url, to), _validate_gz, fresh))


def build(y0: int, y1: int, fresh: bool = False) -> Path:
    import numpy as np
    import xarray as xr

    out = climatology_file(y0, y1)
    stamp = Stamp(f"cru-climatology-{y0}-{y1}", files(), [out], code_hash(sys.modules[__name__], pipeline))
    if not fresh and stamp.up_to_date():
        log(f"  {out.name} is up to date")
        return out
    if missing := stamp.missing_inputs():
        raise SystemExit(f"Missing CRU files ({missing[0].name}, …). Run: download cru")
    clim = {}
    with tempfile.TemporaryDirectory() as t:
        for var in VARS:
            parts = []
            for gz in [p for p in files() if f".{var}." in p.name]:
                nc = Path(t) / gz.name.removesuffix(".gz")
                with gzip.open(gz, "rb") as fi, open(nc, "wb") as fo:
                    shutil.copyfileobj(fi, fo)
                parts.append(xr.open_dataset(nc)[var])
            da = xr.concat(parts, dim="time").sortby("time").sel(time=slice(f"{y0}-01-01", f"{y1}-12-31"))
            if np.issubdtype(da.dtype, np.timedelta64):  # CRU stores wet days as a timedelta
                da = da / np.timedelta64(1, "D")
            clim[var] = da.groupby("time.month").mean("time", skipna=True).sortby("lat", ascending=False).load()
            log(f"  averaged CRU {var} {y0}-{y1}")
    tmp = out.with_name(out.name + ".part")
    xr.Dataset(clim).to_netcdf(tmp)
    tmp.replace(out)
    stamp.done()
    log(f"  wrote {out.name}")
    return out
