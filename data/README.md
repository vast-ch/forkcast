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
| `era5land-rain` | ERA5-Land daily rain totals, one file per year, 1981–2025, 0.25°, world without Antarctica | ~10 GB | Copernicus CDS key needed (see below). 2011–2025 make the climate; the earlier years only the El Niño / La Niña variants. |
| `era5land-temperature` | ERA5-Land monthly mean 2 m temperature for each hour of the day, one file per year, 1981–2025, 0.25° | ~6.7 GB | CDS key needed. The 30 extra years took about 3.5 hours from the CDS. |
| `eurovelo` | Official EuroVelo GPX tracks, one per route, gzipped | 11 MB | ODbL, see `eurovelo/README.md`. |
| `brouter` | Geocodes the hand-made routes' stops (`forkcast_data/geocoded.json`, committed) and routes each leg with BRouter | small | Public servers: Nominatim (1 request/s) and brouter.de. |
| `borders` | Natural Earth country outlines, 1:50m and 1:110m | 2 MB | Public domain. |
| `details` | Natural Earth populated places (1:10m), rivers and lake centerlines and lakes (1:50m) | 12 MB | Public domain. For the map's Cities and Water layers. |
| `oni` | NOAA's Oceanic Niño Index, monthly since 1950 | 10 kB | Decides which months were El Niño or La Niña. |
| `era5land-wind` | ERA5-Land monthly means of the 10 m wind (east and north components) for each hour of the day, one file per year, 2011–2025 | ~5.7 GB | CDS key needed. About 7 min a year. For headwinds (see "Wind"). |
| `cpc` | NOAA CPC Global Unified Temperature: daily highs and lows from weather stations, 0.5°, one file per year and kind, 2011–2025 | 2.4 GB | Public domain (NOAA PSL). How far single days stray from the average (see "How far single days stray"). About 1 min a file. |
| `cyclenet` | OpenStreetMap international bicycle route relations (network `icn`: in Europe essentially EuroVelo, elsewhere little) from the Overpass API: first an index of every route (id, version, box), then each route's ways by id, 10 routes per query, cached per route and version in `cache/cyclenet/icn/` | a few hundred routes | ODbL, © OpenStreetMap contributors. Rotates through public Overpass servers, waits when asked (429), backs off; a route that keeps failing is skipped and listed, and the next run fetches just those. `--fresh` refreshes the index; changed routes are refetched by version. |

### Builds (into `out/`, committed)

| Step | Reads | Writes |
|---|---|---|
| `borders` | `cache/borders/` | `out/countries.json`: the world's country outlines as TopoJSON (each border once, quantized; 231 kB gzipped) |
| `details` | `cache/details/` | `out/places.json` (the world's towns of 50,000 or more and capitals, each with its population and its rank by size in its country, for the map's city setting; 76 kB gzipped) and `out/water.json` (rivers and lakes to 0.01°; 190 kB gzipped). The app fetches each only while its layer is on. |
| `routes` | `eurovelo/`, `cache/brouter/`, `cache/borders/` | `out/routes/<id>.json`, `out/routes/index.json`, `out/routes/overview.json` (all routes simplified to ~1 km, 64 kB gzipped) |
| `cru` | `cache/cru/*.nc.gz` | `cache/cru/climatology-2011-2025.nc` (intermediate) |
| `climate` | ERA5-Land rain and temperature, CRU climatology | `cache/grids/climate.bin` + `climate.json`, the world from 84°N to 60°S, monthly (intermediate) |
| `spread` | `cache/cpc/`, `cache/grids/climate.json` | `cache/grids/spread.npz`: per month and 0.25° cell, how far single days' highs and lows stray from the average (a standard deviation, °C; intermediate, ~8 min) |
| `years` | ERA5-Land rain and temperature, 1981–2025 | `cache/variants/<year>.npz`, each year's monthly fields (intermediate) |
| `variants` | `cache/variants/`, `cache/grids/climate.*` | `cache/grids/climate-<variant>.bin` + `.json` for `last10`, `last5`, `last1`, `elnino`, `lanina`, monthly (intermediate; see "Climate variants") |
| `wind` | `cache/era5land/wind-hourly-*.nc` | `cache/wind/<year>.npz` (each year's monthly wind in riding hours, one stamp per year, ~10 s each), then `cache/grids/wind-<climate>.npz` per climate (intermediate) |
| `pack` | `cache/grids/` (with `spread.npz` and `wind-<climate>.npz`) | `out/climate/<climate>.json` (the header: encoding, tile size, which tiles exist) and `out/climate/<climate>/`: `<lat>_<lon>.bin` per 10° tile with land, for `last15` and each variant: the app's seasonal curves (see "Seasonal curves, packed at build") |
| `cyclenet` | `cache/cyclenet/icn/` | `out/cyclenet.json`: the ways of every route, each once, joined end to end into long lines, simplified to about 300 m. Routes not downloaded yet are reported, not fatal. The app fetches it only when the rider draws with snapping on. |

`all` runs every download, then every build, in the order of these tables.

### Cycle network

The committed `out/cyclenet.json` is still the earlier area-based fetch
(Europe, Africa and Asia, merged from the old per-continent files), made
while every public Overpass server was overloaded; the Americas and Oceania
have none yet (drawing there gives straight lines). `download cyclenet` then
`build cyclenet` replaces it once a server lets the download finish: routes
missing from the cache are left out of a build and reported, so a build from
a half-finished download would ship less than the file has now.

Why by route and not by area: on a busy public Overpass server, what times out
is a query that has to scan a large region (a 20° tile, or a whole continent),
and most of those regions are empty. Asking for routes by id never scans an
area, so each query is quick and its size is set by the routes, not the map.

For drawing routes that follow cycle routes, offline: international routes
only (`icn`), for the whole world. Why not more, measured on Switzerland:

- International routes touching Switzerland: about 2,500 km in 10,161 short
  OSM ways, 107,191 points; 75–85 kB gzipped before joining the ways.
- With regional routes (`rcn`) one 5° tile (45–50°N, 5–10°E) was 206,610 ways
  and about 2 million points, still 415,000 after simplifying to 300 m: far too
  much to ship.
- National routes (`ncn`) would roughly triple Europe; the cache keeps tiles per
  choice of networks (`cache/cyclenet/<networks>/`), so trying them
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

The `climate` build (`forkcast_data/era5land.py`) produces a world
0.25° grid (84°N to 60°S) with twelve months of: mean daily high and low, monthly rain, days
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

### How far single days stray

- **Why:** the averages say what a typical day is like, but a rider meets
  single days. How far they stray depends on the place and season: Moscow's
  January nights by 7 °C (a standard deviation), Singapore's by 1 °C,
  London's summer highs by 3.5 °C. One figure for the world (the help used to
  say "4–6 °C") is wrong for most places.
- **What we download:** NOAA CPC's Global Unified Temperature, the daily
  maximum and minimum of the world's weather stations gridded at 0.5°
  (`cpc`). ERA5-Land's daily extremes would need the slow CDS
  daily-statistics service (see "Highs and lows"); CPC is a plain download.
- **What we measure** (`spread` build, `forkcast_data/cpc.py`): per 0.5° cell,
  each day's departure from the cell's seasonal curve (mean and three yearly
  waves fitted to all 15 years of days), then per month the standard deviation
  of those departures over every year's days in it: day-to-day weather and
  year-to-year differences together, what a rider can meet. Interpolated to
  the climate's 0.25° grid; land cells beyond CPC's coastline take their
  neighbours' value. The averages stay ERA5-Land's; only the spread is CPC's.
- **Stored:** as two more seasonal curves per cell (`tmxsd`, `tmnsd`), with
  the mean and the yearly wave only: 3 bytes each, not 7. The monthly values
  are noisy (15 years of a month's days), and the 3-term curve stays within
  0.5 °C RMS of them. The same in every climate, since how far days stray
  hardly depends on which years are averaged.
- **Used in the app:** each day's usual range, "(9 to 20 °C)", where 8
  days in 10 fall (mean ± 1.28 standard deviations), and the trip's likely
  lowest low and highest high. Those count lows and highs as fewer tries
  than there are, because cold and heat come in spells: one try per 2 lows
  and per 2.5 highs, measured on CPC at 1,200 places (`EXTREME_SPELL` in
  `web/app/utils/itinerary.ts`).
- **Limits:** a normal distribution; real lows have a slightly longer
  tail in winter inland (cold-air pools), so the lowest lows can be a
  degree or two colder than the range says. CPC is sparse where stations are
  (Sahara, Amazon, Siberia's interior): its spread there is interpolated.

### Wind

- **Why:** for a cyclist the wind decides how hard a day is, and which way
  round to ride a route. A steady 15 km/h headwind costs about as much as a
  long climb.
- **What we download:** ERA5-Land's 10 m wind, its east (u) and north (v)
  components, as monthly means for each hour of the day (`era5land-wind`):
  the same fast dataset as the temperatures.
- **What we keep** (`wind` build, `forkcast_data/wind.py`): per month the mean
  wind over the hours people ride, 9:00 to 17:00 local solar time (from each
  cell's longitude), averaged over the climate's years. Wind is calmer at
  night and strongest in the afternoon, so a 24-hour mean would understate
  it.
- **A mean vector, on purpose:** the monthly means average the components, so
  a wind that blows east half the days and west the other half averages to
  nothing. That is exactly what an average headwind needs: against a fixed
  direction, the mean of the push is the push of the mean wind. It does not
  say how windy a place feels, so the app only speaks of the prevailing wind
  and the average head- or tailwind.
- **Per climate:** 2011–2025 and the last 10, 5 and 1 years each average
  their own years; El Niño and La Niña use 2011–2025 (their corrections are
  for temperature and rain).
- **Stored:** two more 7-term seasonal curves per cell (`u10`, `v10`), in
  0.06 m/s steps for the mean, 0.05 m/s for the waves. Monsoons reverse
  through the year, so the shorter waves are needed (with only the yearly
  wave, 0.7 m/s RMS off the monthly values; with all three, 0.4).
- **Checked:** Amsterdam south-westerly, the Rhône valley northerly (the
  Mistral), the Canary Islands north-easterly (the trade winds), Mumbai
  south-westerly in July (the monsoon) and north-easterly in January.
- **In the app:** a day's average headwind is the wind at the middle of the
  day's stretch against the straight line from its start to its end, divided
  by the distance ridden: a winding road's pieces add up to that line, and
  the push of a steady wind adds up the same way.
- **Limits:** 10 m over open ground; valleys, forests and towns are calmer,
  coasts and passes windier. Local winds that come and go within days (a
  sea breeze, a föhn) average out unless they are a regular feature.

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
  10° tile stays about 30 kB. 0.25° (≈ 25 km) still separates
  coasts and valleys far better than CRU's 0.5°; the altitude correction does
  the rest for route points. The CDS regrids to 0.25° on its side, which also
  cuts the downloads.
- **Why one byte per value:** temperatures in 0.5 °C steps, rain on a square-root
  scale (fine steps for dry months, up to about 1,000 mm), rainy days in eighths
  of a day, height in 40 m steps. Each step is well below the real uncertainty
  of the numbers, and it halves the size compared with 16-bit values.
- **Why 10° tiles:** users download only the squares they look at closely
  and ride through, not a continent, and never pick one first. A tile is
  41 × 41 cells: its edge cells are also in its neighbours, so a point is
  interpolated from one tile, without seams (5% more bytes). Only tiles with
  land are written: 317 per climate, 25–40 kB gzipped each, 8.0 MB for the
  whole world. Tile `<lat>_<lon>` is named by its south-west corner.
- **Why no world overview:** the app loads the squares the route crosses and
  the ones the rider clicks on the map, nothing world-wide, so a first visit
  downloads a few hundred kB of climate, not the planet.
- The files get content-hashed names in the app build and are cached by
  browsers for a year.

### Seasonal curves, packed at build

The `climate` and `variants` builds make 12 monthly values per layer, in
`cache/grids/`. The app never uses months as such: it draws each cell's year
as a smooth curve, the yearly mean plus three waves (12-, 6- and 4-month
cycles; see docs/how-it-works.md, "Through the year"), so the map can show
quarter-months and every trip day gets its own value. The `pack` step
(`forkcast_data/pack.py`) fits those curves and publishes their 7 numbers per
layer instead of the 12 months, so the app reads the curves directly:

- **Size:** 42% fewer bytes, about half gzipped (the 6 continents' grids, all
  climates, before tiling: 59.5 → 31.5 MB gzipped).
- **Encoding**, one byte per number, each term its own scale
  (`pack.ENCODING`): mean highs and lows in 0.29 °C steps (from −28 °C for
  highs and −38 °C for lows, the same everywhere: the world's range from
  Greenland to the Sahara fits in a byte), the yearly wave in 0.2 °C steps, the shorter waves in
  0.05 °C; rain's mean on a square-root scale (mm per day) and its waves as a
  share of that mean, so dry places keep their precision; rainy days as the
  share of days. A value outside a scale stops the build instead of being
  clipped.
- **What it costs,** against the same curves unrounded, every day of the
  year: highs and lows 0.1 °C (RMS; at most 0.3 °C), rain 0.24 mm a week
  (RMS; 99.9% of weeks within 1.5 mm), rainy days 0.02 a week.
- **Finer seasons don't pay:** curves fitted to the 15 years of daily rain
  with more waves, or quarter-month values, look sharper but predict other
  years worse. Fitted on 2011, 2013, … 2025 and checked against the even
  years, the error in rainy days per week was 0.58 for today's curves, 0.59
  with 6 waves and 0.67 for quarter-months (rain: 4.7, 4.8 and 5.4 mm a
  week): the extra detail is that sample's weather, not the season's. So a
  monsoon's onset stays softened over about a month.

### Period

2011–2025: 15 years is long enough to average out unusual years and recent
enough to include most of the warming so far. A full 30-year climate normal
would be steadier but about 0.3 °C too cold for today in Europe. Change it
with `--from` / `--to`.

## Climate variants

Besides the 2011–2025 average, the app offers five other climates, one at a
time: the last 10 years, the last 5, the year 2025 alone, a year with El Niño
and a year with La Niña (`forkcast_data/variants.py`; why these and not others, and the research
behind them, in [docs/climate-variants.md](../docs/climate-variants.md)).

- **What a variant is:** the 2011–2025 grid plus a correction, written in the
  same format as `cache/grids/climate-<variant>.bin` / `.json`
  next to `climate.bin`, then packed like it.
  Highs and lows get °C added, rain is multiplied by a ratio (0.5–2, so a dry
  month can't go negative), rainy days get days added (kept within the month,
  r10 ≤ r5 ≤ r1). Where the correction is zero the bytes equal `climate.bin`'s.
  Each packed variant weighs what the 2011–2025 climate does (25 MB, 6.7 MB
  gzipped), committed; the app loads only the one picked, and only its tiles in use.
- **Windows** (`last10`, `last5`): the window's average minus 2011–2025's,
  from the same yearly fields. Building them as corrections, rather than
  re-running the climate build on fewer years, keeps the CRU calibration of
  the full period and skips another hour of building; the difference is the
  per-period calibration offset, a few hundredths of a degree.
- **One year** (`last1`, the period's last: 2025): the same, for a window of one year: each month as it
  was, so riders can try their trip in a real year rather than an average.
  Its rain may change by any factor (0–10×, against 0.5–2× for the averages):
  a single year really can have a month with none, or all of its rain in one
  month (which is why pack's rain waves reach ±2.25× the mean). Its checks
  allow more: an area's mean change in highs of −0.5…+1.5 °C (2025 came out
  +0.1 to +0.7 °C, a hot year) and any cell's highs or lows moving by up to
  15 °C (single winter months in Siberia and Canada came out 13 °C off).
- **El Niño, La Niña:** 15 years hold only 3–4 events of each, too few to
  separate from weather (tested: mostly noise), so the correction is measured
  over 1981–2025. A month is El Niño (La Niña) when NOAA's Oceanic Niño Index
  puts it in an event: at least 5 overlapping seasons in a row at ≥ +0.5 °C
  (≤ −0.5 °C). Per cell and month: remove the linear trend over 1981–2025 (or
  the warming would make El Niño look like "recent"), average the event
  months' departures, and keep that only where it beats 100 random sets of as
  many years: fully beyond their 90th percentile, fading out at the 75th. Then
  smooth over 3 × 3 cells. Months with fewer than 2 event years get no
  correction.
- **Not filtered by other phenomena:** El Niño months include whatever Indian
  Ocean Dipole or volcanic eruption came with them. Leaving out the volcanic
  years (El Chichón, Pinatubo) changed the El Niño average by little and made it no clearer;
  leaving out the IOD+ months weakened it, since the IOD often comes with El
  Niño and is part of what an El Niño year is (docs/climate-variants.md).
- **Checks** (`variants.check`): the build stops, writing nothing, if a
  well-known ENSO effect comes out with the wrong sign (El Niño: drier eastern
  Australian spring, drier northern South America and southern Africa in
  December–February, milder western Canadian winter, wetter US Gulf winter;
  La Niña: the opposite where it's as well established), if a large area's
  (`variants.AREAS`) mean change in highs leaves a plausible range (windows: around the warming,
  phases: near zero), or if any cell's highs or lows move by more than 6 °C.
  A mix-up of months, signs, regions or units trips at least one of them.
  Known flaws of the source data get their own looser limit (`QUIRKS`): on
  the Tibetan Plateau ERA5-Land's winter temperatures jump by up to 14 °C from
  2021 on (likely its snow cover), so the last 5 years warm it by up to
  7.5 °C there, and 2025 alone by up to 14.6 °C. The check found it on its first run. It is in `climate.bin`
  too (4 of its 15 years), uncorrected.
- **Steps:** `download oni` (NOAA, small), `build years` (each year's monthly
  fields into `cache/variants/<year>.npz`, ~110 MB and ~15 s a year, one stamp
  per year), `build variants` (a few minutes). Both need the ERA5-Land
  downloads for 1981–2025.

Research (not a build step, not part of `all`): `variants_research`
compares each variant with the random-year noise floor, per area (`variants.AREAS`), into
`cache/variants/report.md`; its `checks` tests leaving out volcanic years and
Indian Ocean Dipole months (downloading NOAA's Dipole Mode Index first) into
`cache/variants/checks-1981-2025.md`. A few minutes each:

```sh
docker compose --profile tools run --rm --entrypoint uv data run python -m forkcast_data.variants_research          # analyse
docker compose --profile tools run --rm --entrypoint uv data run python -m forkcast_data.variants_research checks
```

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
- **ERA5-Land wind**: covered by the Copernicus notice above.
- **NOAA CPC Global Unified Temperature** (public domain): "CPC Global
  Unified Temperature data provided by the NOAA PSL, Boulder, Colorado, USA,
  from their website at https://psl.noaa.gov".
- **Natural Earth**: public domain; credit is courteous, not required.
