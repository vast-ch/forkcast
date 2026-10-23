# Forkcast data pipeline

Everything the app loads is built here, from public sources, into `out/`
(committed, so the app builds without running any of this). The pipeline is
one Python package, `forkcast_data`, with one command:

```sh
./build.sh all                    # download what is missing, then build what is out of date
./build.sh all --fresh            # redo everything from scratch
./build.sh download <source...>   # one or more download steps
./build.sh build <output...>      # one or more build steps
./build.sh status                 # what is downloaded and what is built
```

`./build.sh` runs `uv run python -m forkcast_data …`. In Docker:
`docker compose --profile tools run --rm data all` (any of the commands above
work after `data`).

## Steps

### Downloads (into `cache/`, git-ignored; EuroVelo tracks into `eurovelo/`, committed)

| Step | What | Size | Notes |
|---|---|---|---|
| `cru` | CRU TS 4.10 monthly grids: tmx, tmn, pre, wet for 2011–2025 | 215 MB | University of East Anglia. Used to calibrate highs and lows. |
| `era5land-rain` | ERA5-Land daily rain totals, one file per year, 0.25°, world without Antarctica | ~3.4 GB | Copernicus CDS key needed (see below). |
| `era5land-temperature` | ERA5-Land monthly mean 2 m temperature for each hour of the day, one file per year, 0.25° | ~4.5 GB | CDS key needed. |
| `eurovelo` | Official EuroVelo GPX tracks, one per route, gzipped | 11 MB | ODbL, see `eurovelo/README.md`. |
| `brouter` | Geocodes the hand-made routes' stops (`forkcast_data/geocoded.json`, committed) and routes each leg with BRouter | small | Public servers: Nominatim (1 request/s) and brouter.de. |
| `borders` | Natural Earth country outlines, 1:50m and 1:110m | 2 MB | Public domain. |

### Builds (into `out/`, committed)

| Step | Reads | Writes |
|---|---|---|
| `borders` | `cache/borders/` | `out/<continent>/countries.json`, `out/world.json` |
| `routes` | `eurovelo/`, `cache/brouter/`, `out/europe/countries.json` | `out/routes/<id>.json`, `out/routes/index.json` |
| `cru` | `cache/cru/*.nc.gz` | `cache/cru/climatology-2011-2025.nc` (intermediate) |
| `climate` | ERA5-Land rain and temperature, CRU climatology | `out/<continent>/climate.bin` + `climate.json` |
| `manifest` | everything above | `out/manifest.json` |

`all` runs every download, then every build, in the order of these tables.
Builds never use the network; a build whose inputs are missing stops and says
which download to run.

## How it decides what to do

**Downloads** are checked, not just looked for. Each file is fetched to
`<name>.part`, validated, and only then renamed into place, so an interrupted
download never looks finished. The checks are:

- gzip files (CRU, EuroVelo) must decompress completely; GPX must contain a track;
- NetCDF files must open, have the expected number of time steps (365/366 days
  of rain, 12 × 24 hours of temperature) on the global 0.25° grid, and their
  last time step must read;
- JSON files must parse and have the expected structure; BRouter legs must hold
  a track of at least two points.

A file that passed is remembered in `cache/.verified.json` by its size and
modification time. Later runs skip it without re-reading it; if the file
changes (or is replaced by a different one), it is checked again, and fetched
again if it fails. Failed fetches are retried three times.

**Builds** leave a stamp in `cache/.stamps/<step>.json` listing the size and
modification time of every input, a hash of the code that builds it, and its
parameters (such as the years). A build is skipped when its stamp still matches
and all its outputs exist. Change an input, the code, or the years, or delete
an output, and it runs again.

**`--fresh`** is passed from `all` down to every step it runs: downloads fetch
every file again (replacing the old one only once the new one has passed its
checks), and builds run regardless of their stamps. Use it on a single step to
redo just that step, e.g. `./build.sh download eurovelo --fresh` to pick up new
EuroVelo tracks. `--fresh` on `brouter` also geocodes every stop again.

**Years**: `--from` and `--to` (default 2011 and 2025) set the climate period
for the ERA5-Land downloads and the `cru` and `climate` builds.

## Copernicus (CDS) access

The ERA5-Land downloads need a free account at
<https://cds.climate.copernicus.eu>, the "Licence to use Copernicus Products"
accepted on the ERA5-Land dataset pages, and the API key in `~/.cdsapirc`:

```
url: https://cds.climate.copernicus.eu/api
key: <your key>
```

The CDS queues requests and rejects more than a few per dataset at once, so
the pipeline sends them one at a time. A year of rain takes about 3–5 minutes;
temperature can wait in the queue longer. Everything already downloaded is
kept, so stopping and restarting loses at most the file in progress.

## How the climate grids are made

See the docstring of `forkcast_data/era5land.py` for the details. In short:
rain totals and rainy-day counts (≥ 1, 5, 10 mm) come straight from ERA5-Land's
daily totals. Highs and lows start from the warmest and coldest hour of
ERA5-Land's average day for each month, then are shifted so that, averaged
over each 0.5° cell, they match CRU's station-based mean daily maximum and
minimum. Values are stored as one byte each on a 0.25° grid, per continent.
