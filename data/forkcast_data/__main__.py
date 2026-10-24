"""Forkcast data pipeline.

    python -m forkcast_data all                     download what is missing, then build what is out of date
    python -m forkcast_data download <source>       one download step
    python -m forkcast_data build <output>          one build step
    python -m forkcast_data <command> ... --fresh   redo everything the command covers, ignoring what is there
    python -m forkcast_data status                  what is downloaded and what is up to date

Downloads (into cache/, except the EuroVelo tracks which are kept in eurovelo/):
    cru                   CRU TS 4.10 monthly grids (calibrates highs and lows)
    era5land-rain         ERA5-Land daily rain totals (Copernicus CDS key needed)
    era5land-temperature  ERA5-Land monthly temperature by hour of day (CDS key needed)
    orography             ERA5-Land terrain height (for the altitude correction)
    eurovelo              official EuroVelo GPX tracks
    brouter               stops geocoded and legs routed for the hand-made routes
    borders               Natural Earth country outlines
    details               Natural Earth places, mountain ranges, rivers and lakes
    cyclenet              OpenStreetMap international cycle routes via Overpass

Builds (into out/, except the CRU climatology which is an intermediate in cache/):
    borders    per-continent outlines and the picker's world map
    details    per-continent city and range names, rivers and lakes
    cyclenet   per-continent cycle network (for drawing along routes)
    routes     every preset route plus the route index
    cru        CRU climatology for the years (intermediate)
    climate    per-continent climate grids (ERA5-Land, calibrated with CRU)
    manifest   the list of continents the app loads first

See data/README.md for how skipping, checking and --fresh work.
"""

from __future__ import annotations

import argparse
import sys
import time

from . import basemap, cru, cyclenet, details, era5land, era5land_download, eurovelo, manifest, routes
from .pipeline import STAMPS, is_verified, log

YEARS = (2011, 2025)


def _years(a) -> range:
    return range(a.y0, a.y1 + 1)


DOWNLOADS = {
    "cru": lambda a: cru.download(a.fresh),
    "era5land-rain": lambda a: era5land_download.rain(_years(a), a.fresh),
    "era5land-temperature": lambda a: era5land_download.temperature(_years(a), a.fresh),
    "orography": lambda a: era5land_download.orography(a.fresh),
    "eurovelo": lambda a: eurovelo.download(a.fresh),
    "brouter": lambda a: routes.download(a.fresh),
    "borders": lambda a: basemap.download(a.fresh),
    "details": lambda a: details.download(a.fresh),
    "cyclenet": lambda a: cyclenet.download(a.fresh),
}

# In dependency order: routes need Europe's borders; the manifest needs everything.
BUILDS = {
    "borders": lambda a: basemap.build(a.fresh),
    "details": lambda a: details.build(a.fresh),
    "routes": lambda a: routes.build(a.fresh),
    "cru": lambda a: cru.build(a.y0, a.y1, a.fresh),
    "climate": lambda a: era5land.build(a.y0, a.y1, a.fresh),
    "manifest": lambda a: manifest.build(a.fresh),
    "cyclenet": lambda a: cyclenet.build(a.fresh),
}


def _run(kind: str, name: str, fn, a) -> None:
    t0 = time.time()
    log(f"{kind} {name}{' (fresh)' if a.fresh else ''}")
    fn(a)
    log(f"  done in {time.time() - t0:.0f} s")


def status(a) -> None:
    y = _years(a)
    groups = {
        "cru": cru.files(),
        "era5land-rain": [era5land_download.rain_file(i) for i in y] + [era5land_download.rain_last_day(y[-1] + 1)],
        "era5land-temperature": [era5land_download.temperature_file(i) for i in y],
        "orography": [era5land_download.orography_file()],
        "eurovelo": [eurovelo.GPX_DIR / f"ev{c[0]}.gpx.gz" for c in eurovelo.CATALOG],
        "borders": [basemap.DIR / n for n in basemap.SOURCES],
        "details": [details.DIR / n for n in details.SOURCES],
        "cyclenet": cyclenet.files(),
    }
    log("downloads (verified / present / expected)")
    for name, files in groups.items():
        have = sum(f.exists() for f in files)
        ok = sum(is_verified(f) for f in files)
        log(f"  {name:22} {ok:3} / {have:3} / {len(files):3}")
    log("builds (stamp in cache/.stamps)")
    for name in BUILDS:
        stamp_files = sorted(STAMPS.glob(f"{'cru-climatology' if name == 'cru' else name}*.json"))
        log(f"  {name:22} {'built ' + time.strftime('%Y-%m-%d %H:%M', time.localtime(stamp_files[-1].stat().st_mtime)) if stamp_files else 'not built'}")


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="python -m forkcast_data", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["all", "download", "build", "status"])
    ap.add_argument("what", nargs="*", help="steps for download/build (default: all of that kind)")
    ap.add_argument("--fresh", action="store_true", help="redo everything the command covers")
    ap.add_argument("--from", dest="y0", type=int, default=YEARS[0], help="first year of the climate period")
    ap.add_argument("--to", dest="y1", type=int, default=YEARS[1], help="last year of the climate period")
    a = ap.parse_args(argv)

    if a.command == "status":
        status(a)
        return
    plan = []
    if a.command in ("all", "download"):
        names = a.what if a.command == "download" and a.what else list(DOWNLOADS)
        plan += [("download", n, DOWNLOADS[n]) for n in names]
    if a.command in ("all", "build"):
        names = a.what if a.command == "build" and a.what else list(BUILDS)
        plan += [("build", n, BUILDS[n]) for n in names]
    unknown = [n for k, n, _ in plan if n not in (DOWNLOADS if k == "download" else BUILDS)]
    if unknown:
        sys.exit(f"Unknown step: {unknown[0]}")
    for kind, name, fn in plan:
        _run(kind, name, fn, a)


if __name__ == "__main__":
    main()
