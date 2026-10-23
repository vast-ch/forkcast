"""Download ERA5-Land daily data from the Copernicus Climate Data Store (CDS).

Needs a CDS account with the "Licence to use Copernicus Products" accepted and
the API key in ~/.cdsapirc. Files go to cache/era5land/ and are skipped when
already present, so the download can be stopped and resumed.

- rain:  total precipitation at 00:00 from `reanalysis-era5-land`. ERA5-Land
         accumulates rain from 00 UTC, so the 00:00 value is the previous
         day's total. 31 December comes from the next year's file (and, for
         the last year, from 1 January of the year after).
- tmax / tmin: daily maximum / minimum 2 m temperature from
         `derived-era5-land-daily-statistics` (computed by the CDS from hourly
         data, which is slow: expect long queues).

Everything is requested on a 0.25° grid (regridded by the CDS) for the world
without Antarctica.

Usage: uv run python -m forkcast_data.era5land_download [rain|tmax|tmin] [--from 2011] [--to 2025]
"""

import argparse
import concurrent.futures as cf
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "cache" / "era5land"
AREA = [84, -180, -60, 180]  # N, W, S, E
GRID = [0.25, 0.25]
DAYS = [f"{d:02d}" for d in range(1, 32)]
MONTHS = [f"{m:02d}" for m in range(1, 13)]


def _retrieve(dataset, request, out: Path):
    import cdsapi  # imported here so the rest of the package works without it

    if out.exists() and out.stat().st_size > 0:
        return f"have {out.name}"
    tmp = out.with_suffix(".part")
    t = time.time()
    for attempt in range(3):
        try:
            cdsapi.Client(quiet=True, progress=False).retrieve(dataset, request, str(tmp))
            tmp.rename(out)
            return f"got {out.name} in {(time.time() - t) / 60:.0f} min, {out.stat().st_size / 1e6:.0f} MB"
        except Exception as e:  # noqa: BLE001 - retry queue/server errors
            if attempt == 2:
                return f"FAILED {out.name}: {str(e)[-300:]}"
            time.sleep(60 * (attempt + 1))


def rain_jobs(years):
    years = list(years)
    for y in years:
        yield (
            "reanalysis-era5-land",
            {
                "variable": ["total_precipitation"],
                "year": str(y),
                "month": MONTHS,
                "day": DAYS,
                "time": ["00:00"],
                "area": AREA,
                "grid": GRID,
                "data_format": "netcdf",
                "download_format": "unarchived",
            },
            CACHE / f"tp00-{y}.nc",
        )
    # Each year's 31 December is the first value of the next year's file;
    # the last year needs 1 January of the year after.
    last = years[-1] + 1
    yield (
        "reanalysis-era5-land",
        {
            "variable": ["total_precipitation"],
            "year": str(last),
            "month": ["01"],
            "day": ["01"],
            "time": ["00:00"],
            "area": AREA,
            "grid": GRID,
            "data_format": "netcdf",
            "download_format": "unarchived",
        },
        CACHE / f"tp00-{last}-01-01.nc",
    )


def temp_jobs(stat, years):
    for y in years:
        for m in MONTHS:
            yield (
                "derived-era5-land-daily-statistics",
                {
                    "variable": ["2m_temperature"],
                    "year": str(y),
                    "month": [m],
                    "day": DAYS,
                    "daily_statistic": f"daily_{stat}",
                    "time_zone": "utc+00:00",
                    "frequency": "1_hourly",
                    "area": AREA,
                    "grid": GRID,
                },
                CACHE / f"t2m-{stat}-{y}-{m}.nc",
            )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["rain", "tmax", "tmin"])
    ap.add_argument("--from", dest="y0", type=int, default=2011)
    ap.add_argument("--to", dest="y1", type=int, default=2025)
    ap.add_argument("--parallel", type=int, default=1, help="concurrent CDS requests (the CDS limits queued requests per dataset)")
    args = ap.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    years = range(args.y0, args.y1 + 1)
    if args.what == "rain":
        jobs = list(rain_jobs(years))
    else:
        jobs = list(temp_jobs("maximum" if args.what == "tmax" else "minimum", years))
    with cf.ThreadPoolExecutor(args.parallel) as ex:
        for msg in ex.map(lambda j: _retrieve(*j), jobs):
            print(msg, flush=True)


if __name__ == "__main__":
    main()
