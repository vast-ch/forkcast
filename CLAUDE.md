# CLAUDE.md

Forkcast monorepo: `web/` (Ember app) and `data/` (Python data builders). See README.md for what it does and how to run it.

The reasoning behind the design is in `docs/how-it-works.md` (app) and `data/README.md` (data). Keep both, and the help page (`web/app/templates/help.gts`, written for riders), in sync when behaviour or data changes.

## Commands

- The web app runs in the `ui` dev container. Run pnpm via `docker compose exec ui <cmd>` (e.g. `docker compose exec ui pnpm lint:types`), never on the host. pnpm only; never npm/yarn/npx.
- Deploys: production is https://forkcast.vast.earth, on Netlify, which builds `web/` from the repository on every push to `main` (`netlify.toml`); the built site is not committed.
- Checks: `./check.sh` runs everything in the containers (web: `pnpm lint`, `pnpm test`; data: `ruff check`, `pytest`); `./check.sh --fix` fixes what the linters can first. Run it before committing.
- Web tests are Ember's (QUnit, `ember-qunit`, `@ember/test-helpers`, `qunit-dom`), by kind: `tests/unit/` for plain logic (`app/utils`), `tests/integration/components|helpers/` for rendering tests, `tests/acceptance/` for whole screens on the real data. Shared finders and assertions are in `tests/helpers/`. `pnpm test` builds into `web/dist-tests` and runs them in the container's Chromium; while developing, open https://ui.forkcast.orb.local/tests to run them live (`?filter=` to pick some). Write new tests the Ember way, not with Vitest.
- No `setTimeout`, `waitUntil` or other polling, in tests or in the app. Async work in the app registers with `@ember/test-waiters` instead, so `await visit()`/`click()` settle when it's done: data files already do (`app/utils/assets.ts` wraps every fetch in `waitForPromise`); wrap any new promise the UI depends on the same way.
- Ruff skips a few style rules in `pipeline.py` and `cru.py` on purpose: build stamps hash module source, so restyling them would force every climate build to rerun.
- Data: `docker compose --profile tools run --rm data [all|status|download …|build …]` (see Data below). Outputs go to `data/out/` (committed). BRouter responses are cached in `data/cache/brouter/`, so re-running `routes` only fetches changed legs; be polite to the public BRouter and Nominatim servers.

## Web app structure

- Routes: `index` (`/`) is the planner (map, panel, chart) and opens on Europe. `help` is the help page (`app/templates/help.gts`) where explanations of the data and calculations live, one tab per section at `/help/<id>` (the tabs and the build's static pages both come from `app/help-sections.json`); keep the planner UI free of long notes. `changelog` (`/changelog`) renders the repository's CHANGELOG.md (mounted or copied into `web/`, see compose.yaml and netlify.toml), so keep entries readable on that page.
- Settings live in the URL: `app/controllers/index.ts` declares them as query parameters with defaults from `app/utils/settings.ts` (Ember omits defaults from the URL), each with a parser in `PARSE` (what the URL holds is checked when read; anything rejected reads as the default). `planner.ts` exposes each as an `@setting` property of the same name. One name and one value per setting, in the URL, the controller and the planner alike. Don't keep old URL keys, help-tab names or localStorage formats working: when something is renamed, it's renamed everywhere. A new setting goes in all three: `DEFAULTS` and `PARSE`, the controller, an `@setting` line. `app/services/last-visit.ts` keeps the whole query string (so every setting, with no per-setting code) and the map's view in localStorage, so opening `/` with no settings picks up where you left off (`IndexRoute.redirect`).
- Privacy is the rule, not the mechanism: nothing about the user (their plan, routes, whereabouts) may reach a server, and the site has none, only static files. The one thing the static host can see is which climate tiles (10° squares) a visitor fetched (the route's and the ones clicked); the help's privacy section says so. Where in the browser things are kept is a design choice: the URL for the plan, so a link shares it; browser storage (localStorage, IndexedDB) is fine for what doesn't fit there or belongs to the device, as long as it never leaves it.
- Data files are imported through `app/utils/assets.ts` (`import.meta.glob` over `/data-out`, the mounted `data/out`), never fetched by fixed path, so they get hashed names and can be cached for a year.
- `app/services/atlas.ts` loads the route list, the world's borders (TopoJSON, `app/utils/topology.ts`) and the climate's header first, then only the climate's 10° tiles the route crosses (`want(purpose, ids)`) or the rider clicks on the map (`pick`, kept in localStorage as `squares`), and a route's track when it is picked. Nothing world-wide loads: `TiledClimate` (`app/utils/climate.ts`) answers each point from its tile, else NaN. There are no continents.
- Your own routes: `app/services/my-routes.ts` keeps them in localStorage (whole tracks, names, a drawn route's clicks); the URL's `routeId` holds one's UUID (`isOwnRouteId`). Anything kept in localStorage is a `@stored(key, parse)` property (`app/utils/stored.ts`): tracked, saved on every write, checked by `parse` when read back. Tests switch the key prefix (`tests/helpers/index.ts`), so running them never touches real data.
- `app/services/planner.ts` is the single place components get state from; derived `route` and `trip` are `@cached`.
- `app/utils/climate.ts` samples the climate grid (bilinear in space, a smooth seasonal curve in time) and owns the temperature colour scale.
- `app/utils/itinerary.ts` splits a route into riding and rest days and attaches weather. `app/utils/route.ts` is geometry and GPX.
- `app/components/wheel-map.gts` wraps Leaflet in a class modifier; `sync()` diffs the state and only rebuilds layers that changed. The temperature layer is rendered into a Web-Mercator canvas (`app/utils/layers.ts`); rain dots are metre-sized circles on a canvas renderer.
- Frontile is used for Switch, SegmentedControl, Input, DatePicker, Chip (`TempPill`) and ButtonGroup with ToggleButton (the map-detail toggles); test new ones with a real click. Plain action buttons are `<button class="wt-btn">`: Frontile's Button once rendered oversized here and its press handling didn't respond to plain clicks.
- Bind inline styles through `css` from `app/utils/format.ts` (htmlSafe) to avoid Ember's style-binding warning.

## Data

- The pipeline is `data/forkcast_data` with one entry point (`./build.sh` / `python -m forkcast_data`): `all`, `status`, `download <source…>`, `build <output…>`, `--fresh`. How skipping, validation and stamps work is documented in `data/README.md`; keep that file in sync when adding or changing a step.
- A new download step uses `pipeline.ensure()` with a real validator; a new build step uses `pipeline.Stamp` with every input file and `code_hash()` of the modules it depends on, and is registered in `forkcast_data/__main__.py` in dependency order.
- Builds never touch the network; downloads are the only steps that do. The CDS needs one request at a time.
- Routes come from OpenStreetMap alone: `forkcast_data/osm.py` downloads the planet and cuts out the bicycle route relations (osmium); `forkcast_data/eurovelo.py` builds the EuroVelo routes from them (shortest path between each route's pinned ends) with heights from the Copernicus terrain model (`forkcast_data/dem.py`), and `forkcast_data/cyclenet.py` the network for drawing. The help page's sources section keeps the full credits (OSM, Copernicus DEM); the map keeps its short line: © OpenStreetMap · EuroVelo · a Credits link to it.
- Hand-made routes are the town lists in `forkcast_data/anchors.py` (the first is the app's default); stops are geocoded into `geocoded.json` by the `brouter` download.
- Map details (city names, rivers, lakes): `forkcast_data/details.py`, one world file each; the app fetches each file only while its layer is on.
- Climate variants (last 10/5 years, 2025 alone, El Niño, La Niña): `forkcast_data/variants.py` builds `climate-<variant>.bin` as the 2011–2025 grid plus a correction and stops the build if known ENSO effects come out wrong (`check`); the app's `climate` setting picks one. Research behind them: `forkcast_data/variants_research.py`, `docs/climate-variants.md`.
- The climate and variants builds write monthly grids to `cache/grids/`; `forkcast_data/pack.py` publishes them to `out/climate/` as the seasonal-curve coefficients the app evaluates (`ClimateGrid`), 7 bytes per layer and cell (3 for the spread of single days' highs and lows, `forkcast_data/cpc.py`, from NOAA CPC's station data), in 10° tiles (`<lat>_<lon>.bin`, south-west corner), nothing world-wide.

## Commits and changelog

- Conventional commits: `feat`, `fix`, `refactor`, `perf`, `docs`, `build`, `chore`, `test`, with a scope where it helps (`web`, `data`), e.g. `feat(web): …`, `fix(data): …`.
- Every user-visible change gets a CHANGELOG.md entry, written for riders, not developers: what changed and why it matters, no file or function names. Headings are `## vX.Y.Z - YYYY-MM-DD` with `### Added` / `### Changed` / `### Fixed`; collect unreleased entries under `## Unreleased`.
- Versions follow semver; tag releases as `vX.Y.Z`.
