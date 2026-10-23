# Wheelther

What the weather usually does along your bike route, day by day.

Wheelther puts 15 years of climate records on a map, one continent at a time (pick it on the world map at `/`; only that continent is downloaded): average day highs or night lows as colour, and rain (mm, or rainy days over 1, 5 or 10 mm) as dots on top, for any month. The in-app help page (`/help`) explains the numbers. Pick a route (all 17 EuroVelo routes and a demo route Interlaken – Málaga are built in, or draw your own, or import a GPX), set a start date, how far you ride per day, and a pattern of riding and rest days (e.g. ride 5, rest 2, repeat), and it lays out the trip day by day with the expected high, night low and chance of rain for where you will be on each date.

## Run it

Everything runs in Docker (OrbStack domains in this setup).

```sh
docker compose up ui                                # dev server, hot reload: https://ui.wheelther.orb.local
docker compose --profile prod up --build web        # production nginx image: https://web.wheelther.orb.local
docker compose --profile tools run --rm data        # rebuild all data into data/out
docker compose --profile tools run --rm data routes # or one step: climate | routes | basemap
```

## Layout

| Path | What |
|---|---|
| `web/` | The app: Ember 7.3 (`.gts`, TypeScript), Vite + Embroider, Leaflet, Tailwind 4, Frontile. pnpm. |
| `data/` | Python (uv) builders for the data files the app loads. |
| `data/out/` | Built data, committed: `manifest.json` (continents and their routes), `world.json` (picker map), `<continent>/climate.bin` + `climate.json` (int16 grid + header), `<continent>/countries.json`, and one `routes/<id>.json` per route. Mounted at `/data-out` in the dev container; the app imports the files as assets, so production builds give them content-hashed names. |
| `data/eurovelo/` | The official EuroVelo GPX tracks (gzipped, ODbL), with their licence. |
| `data/cache/` | Downloads and BRouter responses (git-ignored). |
| `compose.yaml` | `ui` (dev), `web` (prod, profile `prod`), `data` (builder, profile `tools`). |

## Data

- **Climate:** [CRU TS 4.10](https://crudata.uea.ac.uk/cru/data/hrg/) (University of East Anglia), monthly grids at 0.5° (about 50 km), averaged over 2011–2025: mean daily maximum and minimum temperature, precipitation, and wet days (days with at least 0.1 mm). The app interpolates between grid cells and between mid-month values, so every date and place gets its own estimate. Land only; values near coasts come from the nearest land cells.
- **EuroVelo routes:** the official GPX tracks from [EuroVelo.com](https://www.eurovelo.com) (ODbL, see `data/eurovelo/README.md`). The tracks contain variants (both river banks, alternative countries) and spurs; the build treats stages as a network and takes the shortest path from start to finish. Holes between stages are bridged with straight lines: ferries over the sea (not counted as riding), unmapped stretches over land (counted).
- **Demo route:** Interlaken → Rhône valley → Spain's east coast → Málaga (2,369 km), routed town to town with [BRouter](https://brouter.de) (trekking profile), which keeps elevation.
- **Rainy days:** CRU counts wet days at ≥ 0.1 mm. Days over 1, 5 or 10 mm are estimated assuming exponentially distributed wet-day amounts (mean = monthly total ÷ wet days).
- **Basemap:** Natural Earth 1:50m country outlines via `world-atlas`. The app draws its own basemap, so it needs no tile server.

These are climate normals, not forecasts: they say what is typical, not what a given year will bring.

## Static site

There is no backend. The production image is nginx serving the built app:

- Everything under `/assets/` (code and data) has a content hash in its name and is served with `Cache-Control: public, max-age=31536000, immutable`; `index.html` is `no-cache`, so new releases are picked up.
- Every setting lives in the URL query string; values at their defaults are left out. Your own route is encoded in the URL too (polyline encoding, simplified to at most 600 points).
