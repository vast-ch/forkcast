# CLAUDE.md

Wheelther monorepo: `web/` (Ember app) and `data/` (Python data builders). See README.md for what it does and how to run it.

## Commands

- The web app runs in the `ui` dev container. Run pnpm via `docker compose exec ui <cmd>` (e.g. `docker compose exec ui pnpm lint:types`), never on the host. pnpm only; never npm/yarn/npx.
- Checks: `pnpm lint:types`, `pnpm lint:js`, `pnpm lint:hbs`, `pnpm build`.
- Data: `docker compose --profile tools run --rm data [climate|routes|basemap]`. Outputs go to `data/out/` (committed). BRouter responses are cached in `data/cache/brouter/`, so re-running `routes` only fetches changed legs; be polite to the public BRouter and Nominatim servers.

## Web app structure

- Routes: `index` is the planner (map, panel, chart), `help` is the help page (`app/templates/help.gts`) where explanations of the data and calculations live; keep the planner UI free of long notes.
- `app/services/atlas.ts` loads climate, borders and the route index from `/data/`; a route's track loads on demand (`loadRoute`).
- `app/services/planner.ts` holds all UI state (month, layers, selected route, trip settings, user routes) and persists it to localStorage. Derived `route` and `trip` are `@cached`.
- `app/utils/climate.ts` samples the climate grid (bilinear in space, linear between mid-month values in time) and owns the temperature colour scale.
- `app/utils/itinerary.ts` splits a route into riding and rest days and attaches weather. `app/utils/route.ts` is geometry and GPX.
- `app/components/wheel-map.gts` wraps Leaflet in a class modifier; `sync()` diffs the state and only rebuilds layers that changed. The temperature layer is rendered into a Web-Mercator canvas (`app/utils/layers.ts`); rain dots are metre-sized circles on a canvas renderer.
- Frontile is used for Switch, SegmentedControl and Input. Buttons are plain `<button class="wt-btn">`. Frontile's Button rendered oversized here and its press handling didn't respond to plain clicks.
- Bind inline styles through `css` from `app/utils/format.ts` (htmlSafe) to avoid Ember's style-binding warning.

## Data

- EuroVelo routes: `data/wheelther_data/eurovelo.py` (catalogue, GPX → route, variant/gap handling). Raw tracks in `data/eurovelo/` (ODbL; the attribution notice must stay in the help page and map attribution). Refresh with `build.sh download`.
- Hand-made routes are the town lists in `data/wheelther_data/anchors.py` (the first is the app's default). Coordinates come from `geocoded.json`; after adding stops run `uv run python -m wheelther_data.geocode` (Nominatim, only looks up missing ones), then the `routes` step.
- Trip defaults (start 1 January, demo route, ride 5 / rest 1, rainy day > 5 mm) live in `planner.ts`; bump `STORAGE_KEY` when defaults must override what browsers have saved.
- Climate: CRU TS file paths are pinned in `data/build.sh` (version 4.10, 2011–2025).

## Commits and changelog

- Conventional commits: `feat`, `fix`, `refactor`, `perf`, `docs`, `build`, `chore`, `test`, with a scope where it helps (`web`, `data`), e.g. `feat(web): …`, `fix(data): …`.
- Every user-visible change gets a CHANGELOG.md entry, written for riders, not developers: what changed and why it matters, no file or function names. Headings are `## vX.Y.Z - YYYY-MM-DD` with `### Added` / `### Changed` / `### Fixed`; collect unreleased entries under `## Unreleased`.
- Versions follow semver; tag releases as `vX.Y.Z`.
