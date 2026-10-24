# Forkcast

What the weather usually does along your bike route, day by day.

A bikepacking weather planner built on climate records rather than forecasts, so you can plan a trip months ahead.

- **The map:** 15 years of climate records for any week of the year: average day highs or night lows as colour, rain (mm, or rainy days over 1, 5 or 10mm) as dots on top. It opens on Europe; click another continent to add it.
- **Routes:** all 17 EuroVelo routes and a demo route, Interlaken – Málaga, are built in. You can also draw your own or import a GPX, and export any route as GPX.
- **The trip:** set a start date, km per day, average speed and a pattern of riding and rest days (e.g. ride 5, rest 2, repeat).
- **Each day:** the expected high, night low and chance of rain where you'll be on that date, plus climbing, riding time and hours of daylight. A 🔦 marks days with more riding than daylight.
- **In sync:** the day chart and the map's week move together, and the whole plan lives in the link, so a bookmark or a shared URL reopens it.

The in-app help page (`/help`) explains where the numbers come from and how far to trust them.

How the app works and why it is built this way: [docs/how-it-works.md](docs/how-it-works.md). How the data is made: [data/README.md](data/README.md).

## Run it

Everything runs in Docker (OrbStack domains in this setup).

```sh
docker compose up ui                                # dev server, hot reload: https://ui.forkcast.orb.local
docker compose --profile prod up --build web        # production nginx image: https://web.forkcast.orb.local
docker compose --profile tools run --rm data        # data pipeline: download what's missing, build what's stale
docker compose --profile tools run --rm data status # see data/README.md for steps and --fresh
./check.sh                                          # lint and test web and data (--fix to auto-fix first)
# web tests live in the browser while developing: https://ui.forkcast.orb.local/tests
```

### Static build

```sh
docker compose exec ui pnpm build                   # writes web/dist
```

`web/dist` is the whole site, data included (about 59 MB; a visitor only downloads the continents they show, 0.7–4.8 MB gzipped each): upload it to any static host.

- **Serve it from the domain root.** Asset URLs are absolute (`/assets/…`); a sub-path such as `example.com/forkcast/` needs `rootURL` in `web/config/environment.js` and Vite's `base` changed to match.
- **Deep links work without rewrite rules:** the build writes `help/index.html`, one `help/<section>/index.html` per help tab (`web/app/help-sections.json`) and a `404.html` fallback, all copies of `index.html`. Settings live in the query string, so the planner's links are all `/`.
- **Caching:** everything under `/assets/` has a content hash in its name and can be cached for a year (`immutable`); the HTML pages should be `no-cache`. `web/nginx.conf` does exactly that.
- **Privacy headers:** a content security policy that only allows the site's own files, `Referrer-Policy: no-referrer` and no ad topics. `web/public/_headers` sets them on Netlify (it ends up in `web/dist`), `web/security-headers.conf` in the nginx image; on another host, set the same headers.

## Layout

| Path | What |
|---|---|
| `web/` | The app: Ember 7.3 (`.gts`, TypeScript), Vite + Embroider, Leaflet, Tailwind 4, Frontile. pnpm. |
| `data/` | Python (uv) builders for the data files the app loads. |
| `data/out/` | Built data, committed: `manifest.json` (continents and their routes), `world.json` (picker map), `<continent>/climate.bin` + `climate.json` (byte grid + header), `<continent>/countries.json`, and one `routes/<id>.json` per route. Mounted at `/data-out` in the dev container; the app imports the files as assets, so production builds give them content-hashed names. |
| `data/eurovelo/` | The official EuroVelo GPX tracks (gzipped, ODbL), with their licence. |
| `data/cache/` | Downloads and BRouter responses (git-ignored). |
| `compose.yaml` | `ui` (dev), `web` (prod, profile `prod`), `data` (builder, profile `tools`). |

## Data

How the data is downloaded and built, and how the pipeline decides what to redo, is in [data/README.md](data/README.md).

- **Climate:** [ERA5-Land](https://cds.climate.copernicus.eu/datasets/reanalysis-era5-land) (Copernicus Climate Change Service), 2011–2025, on a 0.25° grid (about 25 km): rain from the daily totals (rainy days over 1, 5 and 10 mm are counted), highs and lows from the average day's temperature curve calibrated against [CRU TS 4.10](https://crudata.uea.ac.uk/cru/data/hrg/) station-based daily extremes.
- **EuroVelo routes:** the official GPX tracks from [EuroVelo.com](https://www.eurovelo.com) (ODbL, see `data/eurovelo/README.md`). Variants and spurs are resolved by taking the shortest path through the stages; holes between stages over the sea count as ferries.
- **Demo route:** Interlaken → Rhône valley → Spain's east coast → Málaga, routed town to town with [BRouter](https://brouter.de) (trekking profile).
- **Cycle routes for drawing:** international bicycle routes from © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors, fetched with the Overpass API; the derived per-continent files are under the [ODbL](https://opendatacommons.org/licenses/odbl/1-0/).
- **Borders, cities, mountain ranges, rivers and lakes:** Natural Earth (public domain). The relief shading is drawn from the climate data's terrain height.
- **Daylight:** calculated from the sun's position for each day's start and end; no data needed.

These are climate normals, not forecasts: they say what is typical, not what a given year will bring.

## Static site

There is no backend. The production image is nginx serving the built app:

- Everything under `/assets/` (code and data) has a content hash in its name and is served with `Cache-Control: public, max-age=31536000, immutable`; `index.html` is `no-cache`, so new releases are picked up.
- Every setting lives in the URL query string; values at their defaults are left out. Your own routes are kept whole in the browser's localStorage, never on a server; the URL names one by its UUID.
