"""Download ERA5-Land from the Copernicus Climate Data Store (CDS).

Needs a CDS account with the "Licence to use Copernicus Products" accepted and
the API key in ~/.cdsapirc. Requests go one at a time (the CDS rejects more
than a few queued requests per dataset). Everything is requested on a 0.25°
grid (regridded by the CDS) for the world without Antarctica.

- rain: total precipitation at 00:00 from `reanalysis-era5-land`, one file per
  year (cache/era5land/tp00-<year>.nc). ERA5-Land accumulates rain from
  00 UTC, so the 00:00 value is the previous day's total. 31 December comes
  from the next year's file; for the last year, from tp00-<year+1>-01-01.nc.
- temperature: monthly means of 2 m temperature for each hour of the day from
  `reanalysis-era5-land-monthly-means` (product "by hour of day"), one file per
  year (cache/era5land/t2m-hourly-<year>.nc, 12 months × 24 hours). The daily
  maximum and minimum are derived from it in era5land.py.
- wind: the same, for the 10 m wind's east and north components
  (cache/era5land/wind-hourly-<year>.nc), for which way the wind blows.
- wind speed: the same from ERA5 (`reanalysis-era5-single-levels-monthly-means`,
  same 0.25° grid), for the 10 m wind speed: the mean of each hour's speed,
  which ERA5-Land lacks. Averaging the components instead lets winds from
  different sides cancel (cache/era5land/wspd-hourly-<year>.nc).
- dewpoint: the same, for the 2 m dewpoint (cache/era5land/d2m-hourly-<year>.nc),
  for how humid the afternoon is (heat stress).
- snow: monthly means of snow cover, % of the cell
  (cache/era5land/snow-<year>.nc), for snow on high passes.

- orography: ERA5-Land's surface geopotential (its model terrain) at 0.1°,
  published by ECMWF (cache/era5land/orography-0.1.nc, 52 MB, no key needed).
  Used to store each cell's mean height, for the altitude correction.

Usage: uv run python -m forkcast_data download era5land-rain|era5land-temperature|era5land-wind|era5-wind-speed|era5land-dewpoint|era5land-snow|orography [--fresh]
"""

from __future__ import annotations

import calendar
from pathlib import Path

from .pipeline import CACHE, ensure, log

DIR = CACHE / "era5land"
AREA = [84, -180, -60, 180]  # N, W, S, E
GRID = [0.25, 0.25]
DAYS = [f"{d:02d}" for d in range(1, 32)]
MONTHS = [f"{m:02d}" for m in range(1, 13)]
HOURS = [f"{h:02d}:00" for h in range(24)]


def _cds(dataset: str, request: dict):
    def fetch(to: Path) -> None:
        import cdsapi  # only needed for downloads

        cdsapi.Client(quiet=True, progress=False).retrieve(dataset, request, str(to))

    return fetch


def _check_times(expected: int):
    def validate(path: Path) -> None:
        import xarray as xr

        with xr.open_dataset(path) as ds:
            var = next(v for v in ds.data_vars if ds[v].ndim >= 3)
            da = ds[var]
            n = 1
            for d in da.dims:
                if d not in ("latitude", "longitude", "lat", "lon"):
                    n *= da.sizes[d]
            if n != expected:
                raise ValueError(f"{n} time steps, expected {expected}")
            if da.sizes.get("latitude", da.sizes.get("lat", 0)) < 500:
                raise ValueError("not the global 0.25° grid")
            # Read the last time step so a file cut short or damaged near its
            # end fails here, not halfway through a build.
            last = da.isel({da.dims[0]: -1}).values
            if not (last == last).any():
                raise ValueError("last time step has no data")

    return validate


def rain_file(year: int) -> Path:
    return DIR / f"tp00-{year}.nc"


def rain_last_day(year: int) -> Path:
    return DIR / f"tp00-{year}-01-01.nc"


def temperature_file(year: int) -> Path:
    return DIR / f"t2m-hourly-{year}.nc"


def wind_file(year: int) -> Path:
    return DIR / f"wind-hourly-{year}.nc"


def wind_speed_file(year: int) -> Path:
    return DIR / f"wspd-hourly-{year}.nc"


def dewpoint_file(year: int) -> Path:
    return DIR / f"d2m-hourly-{year}.nc"


def snow_file(year: int) -> Path:
    return DIR / f"snow-{year}.nc"


def rain(years: range, fresh: bool = False) -> None:
    for y in years:
        req = {
            "variable": ["total_precipitation"],
            "year": str(y),
            "month": MONTHS,
            "day": DAYS,
            "time": ["00:00"],
            "area": AREA,
            "grid": GRID,
            "data_format": "netcdf",
            "download_format": "unarchived",
        }
        n = 366 if calendar.isleap(y) else 365
        log("  " + ensure(rain_file(y), _cds("reanalysis-era5-land", req), _check_times(n), fresh))
    last = years[-1] + 1
    req = {
        "variable": ["total_precipitation"],
        "year": str(last),
        "month": ["01"],
        "day": ["01"],
        "time": ["00:00"],
        "area": AREA,
        "grid": GRID,
        "data_format": "netcdf",
        "download_format": "unarchived",
    }
    log("  " + ensure(rain_last_day(last), _cds("reanalysis-era5-land", req), _check_times(1), fresh))


def _by_hour(years: range, variables: list[str], file, fresh: bool, dataset: str = "reanalysis-era5-land-monthly-means") -> None:
    """Monthly means for each hour of the day, one file per year (12 months × 24 hours)."""
    for y in years:
        req = {
            "product_type": ["monthly_averaged_reanalysis_by_hour_of_day"],
            "variable": variables,
            "year": [str(y)],
            "month": MONTHS,
            "time": HOURS,
            "area": AREA,
            "grid": GRID,
            "data_format": "netcdf",
            "download_format": "unarchived",
        }
        log("  " + ensure(file(y), _cds(dataset, req), _check_times(12 * 24), fresh))


def temperature(years: range, fresh: bool = False) -> None:
    _by_hour(years, ["2m_temperature"], temperature_file, fresh)


def wind(years: range, fresh: bool = False) -> None:
    _by_hour(years, ["10m_u_component_of_wind", "10m_v_component_of_wind"], wind_file, fresh)


def wind_speed(years: range, fresh: bool = False) -> None:
    _by_hour(years, ["10m_wind_speed"], wind_speed_file, fresh, "reanalysis-era5-single-levels-monthly-means")


def dewpoint(years: range, fresh: bool = False) -> None:
    _by_hour(years, ["2m_dewpoint_temperature"], dewpoint_file, fresh)


def snow(years: range, fresh: bool = False) -> None:
    for y in years:
        req = {
            "product_type": ["monthly_averaged_reanalysis"],
            "variable": ["snow_cover"],
            "year": [str(y)],
            "month": MONTHS,
            "time": ["00:00"],
            "area": AREA,
            "grid": GRID,
            "data_format": "netcdf",
            "download_format": "unarchived",
        }
        log("  " + ensure(snow_file(y), _cds("reanalysis-era5-land-monthly-means", req), _check_times(12), fresh))


OROGRAPHY_URL = "https://confluence.ecmwf.int/download/attachments/140385202/geo_1279l4_0.1x0.1.grib2_v4_unpack.nc"


def orography_file() -> Path:
    return DIR / "orography-0.1.nc"


def _check_orography(path: Path) -> None:
    import xarray as xr

    with xr.open_dataset(path) as ds:
        z = ds["z"]
        if z.sizes.get("latitude", 0) < 1800 or z.sizes.get("longitude", 0) < 3600:
            raise ValueError("not the global 0.1° grid")
        if not float(z.max()) > 50000:  # Himalaya ≈ 8 km × 9.8 m/s²
            raise ValueError("no mountains in the terrain file")


def orography(fresh: bool = False) -> None:
    from .pipeline import http_get

    log("  " + ensure(orography_file(), lambda to: http_get(OROGRAPHY_URL, to), _check_orography, fresh))
