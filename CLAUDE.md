# CLAUDE.md

Forkcast monorepo: `web/` (Ember app) and `data/` (Python data builders). See README.md for what it does and how to run it.

The reasoning behind the design is in `docs/how-it-works.md` (app) and `data/README.md` (data). Keep both, and the help page (`web/app/templates/help.gts`, written for riders), in sync when behaviour or data changes.

## Commands

- The web app runs in the `ui` dev container. Run pnpm via `docker compose exec ui <cmd>` (e.g. `docker compose exec ui pnpm lint:types`), never on the host. pnpm only; never npm/yarn/npx.
- Checks: `./check.sh` runs everything in the containers (web: `pnpm lint`, `pnpm test`; data: `ruff check`, `pytest`); `./check.sh --fix` fixes what the linters can first. Run it before committing.
- Web tests are Ember's (QUnit, `ember-qunit`, `@ember/test-helpers`, `qunit-dom`), by kind: `tests/unit/` for plain logic (`app/utils`), `tests/integration/components|helpers/` for rendering tests, `tests/acceptance/` for whole screens on the real data. Shared finders and assertions are in `tests/helpers/`. `pnpm test` builds into `web/dist-tests` and runs them in the container's Chromium; while developing, open https://ui.forkcast.orb.local/tests to run them live (`?filter=` to pick some). Write new tests the Ember way, not with Vitest.
- No `setTimeout`, `waitUntil` or other polling, in tests or in the app. Async work in the app registers with `@ember/test-waiters` instead, so `await visit()`/`click()` settle when it's done: data files already do (`app/utils/assets.ts` wraps every fetch in `waitForPromise`); wrap any new promise the UI depends on the same way.
- Ruff skips a few style rules in `pipeline.py`, `cru.py` and `era5land.py` on purpose: build stamps hash module source, so restyling them would force hours of climate rebuilds.
- Data: `docker compose --profile tools run --rm data [climate|routes|basemap]`. Outputs go to `data/out/` (committed). BRouter responses are cached in `data/cache/brouter/`, so re-running `routes` only fetches changed legs; be polite to the public BRouter and Nominatim servers.

## Web app structure

- Routes: `index` (`/`) is the planner (map, panel, chart) and opens on Europe; other continents are added when clicked on the map (`?continents=europe,asia`); they never replace each other. `help` is the help page (`app/templates/help.gts`) where explanations of the data and calculations live, one tab per section at `/help/<id>` (the tabs and the build's static pages both come from `app/help-sections.json`); keep the planner UI free of long notes.
- Settings live in the URL: `app/controllers/index.ts` declares them as query parameters with defaults from `app/utils/settings.ts` (Ember omits defaults from the URL); `planner.ts` reads and writes them. Add a new setting in both places. No localStorage.
- Data files are imported through `app/utils/assets.ts` (`import.meta.glob` over `/data-out`, the mounted `data/out`), never fetched by fixed path, so they get hashed names and can be cached for a year.
- `app/services/atlas.ts` loads the manifest and picker map first, a continent's climate grid and borders when it is opened, and a route's track when it is picked.
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
- EuroVelo routes: `forkcast_data/eurovelo.py`. Raw tracks in `data/eurovelo/` (ODbL; the full attribution notice stays on the help page's sources section, and the map keeps its short line: © OpenStreetMap · EuroVelo · a Credits link to it).
- Hand-made routes are the town lists in `forkcast_data/anchors.py` (the first is the app's default); stops are geocoded into `geocoded.json` by the `brouter` download.
- Continents (ids, names, bounding boxes) are in `forkcast_data/continents.py`.
- Map details (city and range names, rivers, lakes): `forkcast_data/details.py`, per continent; the app fetches each file only while its layer is on.

## Commits and changelog

- Conventional commits: `feat`, `fix`, `refactor`, `perf`, `docs`, `build`, `chore`, `test`, with a scope where it helps (`web`, `data`), e.g. `feat(web): …`, `fix(data): …`.
- Every user-visible change gets a CHANGELOG.md entry, written for riders, not developers: what changed and why it matters, no file or function names. Headings are `## vX.Y.Z - YYYY-MM-DD` with `### Added` / `### Changed` / `### Fixed`; collect unreleased entries under `## Unreleased`.
- Versions follow semver; tag releases as `vX.Y.Z`.
