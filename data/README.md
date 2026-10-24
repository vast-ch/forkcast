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
| `details` | Natural Earth populated places and geography regions (1:10m), rivers and lake centerlines and lakes (1:50m) | 12 MB | Public domain. For the map's Cities and Water layers. |
| `cyclenet` | OpenStreetMap international bicycle route relations (network `icn`: in Europe essentially EuroVelo, elsewhere little) from the Overpass API: first an index of every route (id, version, box), then each route's ways by id, 10 routes per query, cached per route and version in `cache/cyclenet/icn/` | a few hundred routes | ODbL, © OpenStreetMap contributors. Rotates through public Overpass servers, waits when asked (429), backs off; a route that keeps failing is skipped and listed, and the next run fetches just those. `--fresh` refreshes the index; changed routes are refetched by version. |

### Builds (into `out/`, committed)

| Step | Reads | Writes |
|---|---|---|
| `borders` | `cache/borders/` | `out/<continent>/countries.json`, `out/world.json` |
| `details` | `cache/details/` | `out/<continent>/places.json` (towns of 50,000 or more and capitals, mountain-range names at the centre of their area; Europe 14 kB gzipped) and `out/<continent>/water.json` (rivers and lakes to 0.01°; Europe 29 kB gzipped). The app fetches each only while its layer is on. |
| `routes` | `eurovelo/`, `cache/brouter/`, `out/europe/countries.json` | `out/routes/<id>.json`, `out/routes/index.json`, `out/routes/overview.json` (all routes simplified to ~1 km, 64 kB gzipped) |
| `cru` | `cache/cru/*.nc.gz` | `cache/cru/climatology-2011-2025.nc` (intermediate) |
| `climate` | ERA5-Land rain and temperature, CRU climatology | `out/<continent>/climate.bin` + `climate.json` |
| `manifest` | everything above | `out/manifest.json` |
| `cyclenet` | `cache/cyclenet/icn/` | `out/<continent>/cyclenet.json`: the ways of every route whose box touches the continent, each once, joined end to end into long lines, simplified to about 300 m. Routes not downloaded yet are reported, not fatal. The app fetches a continent's file only when it is shown and the rider draws with snapping on. |

`all` runs every download, then every build, in the order of these tables.

### Cycle network

Why by route and not by area: on a busy public Overpass server, what times out
is a query that has to scan a large region (a 20° tile, or a whole continent),
and most of those regions are empty. Asking for routes by id never scans an
area, so each query is quick and its size is set by the routes, not the map.

For drawing routes that follow cycle routes, offline: international routes
only (`icn`), for every continent. Why not more, measured on Switzerland:

- International routes touching Switzerland: about 2,500 km in 10,161 short
  OSM ways, 107,191 points; 75–85 kB gzipped before joining the ways.
- With regional routes (`rcn`) one 5° tile (45–50°N, 5–10°E) was 206,610 ways
  and about 2 million points, still 415,000 after simplifying to 300 m: far too
  much to ship for a continent.
- National routes (`ncn`) would roughly triple Europe; the cache keeps tiles per
  choice of networks (`cache/cyclenet/<continent>/<networks>/`), so trying them
  later doesn't mix with these.

Builds never use the network; a build whose inputs are missing stops and says
which download to run.

## How it decides what to do

Why this matters: a full run downloads about 8 GB from servers that queue and
throttle requests, and some steps take a while. Interrupting it, changing one
step, or rerunning it should cost only what actually changed, and a broken or
half-written file must never be mistaken for a good one.

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

## How the climate grids are made, and why

The `climate` build (`forkcast_data/era5land.py`) produces, per continent, a
0.25° grid with twelve months of: mean daily high and low, monthly rain, days
with at least 1, 5 and 10 mm of rain, plus each cell's mean terrain height.

### Sources

**ERA5-Land** (Copernicus Climate Change Service, run by ECMWF) is a
reanalysis: a weather model re-run over past decades and continuously
corrected with observations, giving every hour of every day on a 0.1° grid
(about 9 km) over all land. We use it because it is global, consistent across
countries, recent, and fine enough to separate a coast from the hills behind
it. Its weakness: like any model it smooths the extremes of a day.

**CRU TS 4.10** (Climatic Research Unit, University of East Anglia) is built
from weather-station records interpolated to 0.5° (about 50 km). Its monthly
mean daily maximum and minimum are averages of what thermometers actually
recorded. It is coarse, but the level of its highs and lows is right. The
app's first version used it alone; now it calibrates ERA5-Land.

### Rain

- **What:** `total_precipitation` at 00:00 UTC for every day, 2011–2025.
- **Why 00:00:** ERA5-Land accumulates rain from 00 UTC, so the 00:00 value is
  the previous day's total. One field per day instead of 24 keeps the download
  at about 220 MB per year. The cost is a shift to UTC days, which hardly
  matters for monthly counts.
- **Rainy days are counted, not estimated:** for each day and cell we check
  whether the total reached 1, 5 and 10 mm and average the counts per month
  over the years. (CRU only counts days ≥ 0.1 mm, which forced the app's first
  version to estimate the other thresholds with an exponential model.)

### Highs and lows

- **What we download:** ERA5-Land's *monthly means for each hour of the day*:
  for every month, 24 numbers per cell, the average temperature at 00:00,
  01:00, … 23:00.
- **Why not daily maxima and minima directly:** the CDS can compute them
  (`derived-era5-land-daily-statistics`), but on request and through a long
  queue: a single month waited over two hours without starting. The full
  period would need around 360 such requests, i.e. weeks. The hourly monthly
  means come from a fast, precomputed dataset (3–5 minutes per year).
- **The catch:** the warmest hour of the *average* day is cooler than the
  *average* daily maximum, because on real days the maximum falls at different
  hours and varies in size. The same holds, the other way round, for the
  minimum. Over 2011–2025 the median gap is 1.4–1.8 °C for highs and 1.1–2.0 °C for lows depending on the month (the build logs it), and it varies by place.
- **The fix, calibration against CRU:** for each month and each 0.5° CRU
  cell, compare CRU's mean daily maximum with ERA5-Land's warmest hour
  averaged over the same cell. The difference (the offset) is filled in where
  CRU has no cell (small islands, coasts) from the nearest cells that have
  one, smoothed over neighbouring cells, interpolated to 0.25° and added to
  ERA5-Land's warmest hour. The same is done for the lows with the coldest hour.
  Result: ERA5-Land's spatial detail at CRU's measured level. The build logs
  the median offset per month so a change in the sources shows up.

### Altitude

- **Why:** a 0.25° cell is about 25 km across; in mountains its mean height can
  differ from a valley town or a pass on the route by hundreds of metres, and
  air cools about 6.5 °C per 1,000 m. Without a correction, Interlaken (568 m)
  read like its 920 m cell, more than 2 °C too cold.
- **What we store:** each cell's mean height, from ERA5-Land's own 0.1°
  terrain (the `orography` download, 52 MB, published by ECMWF), averaged to
  0.25°.
- **Where it is applied:** in the app, not here. Route points know their
  height (from the GPX or BRouter tracks), so the app shifts a day's high and low by the month's lapse rate times the height difference between the route and the cell: from 4.4 °C per 1,000 m in December to 6.8 °C in June–July (seasonal rates measured across the Alps, Rolland 2003; `LAPSE_RATES` in `web/app/utils/climate.ts`). The map itself shows cell averages.
- **Limits, measured:** against published town climates (2011–2025 data, corrected to town height) summer highs are within about 1 °C (Madrid 33.6 vs 33, Seville 37.0 vs 36, Interlaken 24.8 vs 24, Bergen 18.0 vs 19). Winter in Alpine valleys stays 2–3 °C too mild (Interlaken January high 6 vs 3) and nights more: cold-air pooling and fog are local effects neither the grid nor a lapse rate captures. A constant 6.5 °C/km made winter worse, which is why the rate is seasonal.

### Size and format

- **Why 0.25° and not ERA5-Land's native 0.1°:** six times fewer cells, so a
  continent stays a download of a few MB. 0.25° (≈ 25 km) still separates
  coasts and valleys far better than CRU's 0.5°; the altitude correction does
  the rest for route points. The CDS regrids to 0.25° on its side, which also
  cuts the downloads.
- **Why one byte per value:** temperatures in 0.5 °C steps, rain on a square-root
  scale (fine steps for dry months, up to about 1,000 mm), rainy days in eighths
  of a day, height in 40 m steps. Each step is well below the real uncertainty
  of the numbers, and it halves the size compared with 16-bit values.
- **Why per continent:** users download only the part of the world they plan
  in. The files get content-hashed names in the app build and are cached by
  browsers for a year.

### Monthly values, smooth in the app

The grids hold monthly values; the app fits a smooth seasonal curve through
them per cell (see docs/how-it-works.md, "Through the year"), so the map can
show quarter-months and every trip day gets its own value without bigger
downloads. Known trade-off: sharp seasonal edges, such as the start of a
monsoon, are softened. Improvement left for later: compute weekly rain totals
and rainy-day counts from the daily rain already in `cache/era5land/` and
store those (or their seasonal-curve coefficients) instead of monthly rain.

### Period

2011–2025: 15 years is long enough to average out unusual years and recent
enough to include most of the warming so far. A full 30-year climate normal
would be steadier but about 0.3 °C too cold for today in Europe. Change it
with `--from` / `--to`.

## Licences and attribution

These notices are required and must stay in the app (help page "Sources and
licences" and the map's attribution line) whenever the data is published:

- **ERA5-Land** (Copernicus Licence): "Contains modified Copernicus Climate
  Change Service information <year>; neither the European Commission nor ECMWF
  is responsible for any use that may be made of the Copernicus information or
  data it contains."
- **EuroVelo tracks** (ODbL): "Contains information from EuroVelo GPX tracks
  downloaded from www.EuroVelo.com on <date>, which is made available here
  under the Open Database License (ODbL)." Derived route files stay under the
  ODbL (see `eurovelo/README.md`).
- **OpenStreetMap** (ODbL), via BRouter for the demo route: "© OpenStreetMap
  contributors".
- **CRU TS** (Open Database License, as linked from the CRU TS download
  page): credit the Climatic Research Unit, University of East Anglia; the
  climatology derived from it stays under the ODbL.
- **Natural Earth**: public domain; credit is courteous, not required.
