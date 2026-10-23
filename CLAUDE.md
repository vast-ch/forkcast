# CLAUDE.md

Forkcast monorepo: `web/` (Ember app) and `data/` (Python data builders). See README.md for what it does and how to run it.

The reasoning behind the design is in `docs/how-it-works.md` (app) and `data/README.md` (data). Keep both, and the help page (`web/app/templates/help.gts`, written for riders), in sync when behaviour or data changes.

## Commands

- The web app runs in the `ui` dev container. Run pnpm via `docker compose exec ui <cmd>` (e.g. `docker compose exec ui pnpm lint:types`), never on the host. pnpm only; never npm/yarn/npx.
- Checks: `pnpm lint:types`, `pnpm lint:js`, `pnpm lint:hbs`, `pnpm build`.
- Data: `docker compose --profile tools run --rm data [climate|routes|basemap]`. Outputs go to `data/out/` (committed). BRouter responses are cached in `data/cache/brouter/`, so re-running `routes` only fetches changed legs; be polite to the public BRouter and Nominatim servers.

## Web app structure

- Routes: `index` is the continent picker (world map), `continent` (`/:continent_id`) is the planner (map, panel, chart), `help` is the help page (`app/templates/help.gts`) where explanations of the data and calculations live; keep the planner UI free of long notes.
- Settings live in the URL: `app/controllers/continent.ts` declares them as query parameters with defaults from `app/utils/settings.ts` (Ember omits defaults from the URL); `planner.ts` reads and writes them. Add a new setting in both places. No localStorage.
- Data files are imported through `app/utils/assets.ts` (`import.meta.glob` over `/data-out`, the mounted `data/out`), never fetched by fixed path, so they get hashed names and can be cached for a year.
- `app/services/atlas.ts` loads the manifest and picker map first, a continent's climate grid and borders when it is opened, and a route's track when it is picked.
- `app/services/planner.ts` is the single place components get state from; derived `route` and `trip` are `@cached`.
- `app/utils/climate.ts` samples the climate grid (bilinear in space, linear between mid-month values in time) and owns the temperature colour scale.
- `app/utils/itinerary.ts` splits a route into riding and rest days and attaches weather. `app/utils/route.ts` is geometry and GPX.
- `app/components/wheel-map.gts` wraps Leaflet in a class modifier; `sync()` diffs the state and only rebuilds layers that changed. The temperature layer is rendered into a Web-Mercator canvas (`app/utils/layers.ts`); rain dots are metre-sized circles on a canvas renderer.
- Frontile is used for Switch, SegmentedControl and Input. Buttons are plain `<button class="wt-btn">`. Frontile's Button rendered oversized here and its press handling didn't respond to plain clicks.
- Bind inline styles through `css` from `app/utils/format.ts` (htmlSafe) to avoid Ember's style-binding warning.

## Data

- The pipeline is `data/forkcast_data` with one entry point (`./build.sh` / `python -m forkcast_data`): `all`, `status`, `download <source…>`, `build <output…>`, `--fresh`. How skipping, validation and stamps work is documented in `data/README.md`; keep that file in sync when adding or changing a step.
- A new download step uses `pipeline.ensure()` with a real validator; a new build step uses `pipeline.Stamp` with every input file and `code_hash()` of the modules it depends on, and is registered in `forkcast_data/__main__.py` in dependency order.
- Builds never touch the network; downloads are the only steps that do. The CDS needs one request at a time.
- EuroVelo routes: `forkcast_data/eurovelo.py`. Raw tracks in `data/eurovelo/` (ODbL; the attribution notice must stay in the help page and map attribution).
- Hand-made routes are the town lists in `forkcast_data/anchors.py` (the first is the app's default); stops are geocoded into `geocoded.json` by the `brouter` download.
- Continents (ids, names, bounding boxes) are in `forkcast_data/continents.py`.

## Commits and changelog

- Conventional commits: `feat`, `fix`, `refactor`, `perf`, `docs`, `build`, `chore`, `test`, with a scope where it helps (`web`, `data`), e.g. `feat(web): …`, `fix(data): …`.
- Every user-visible change gets a CHANGELOG.md entry, written for riders, not developers: what changed and why it matters, no file or function names. Headings are `## vX.Y.Z - YYYY-MM-DD` with `### Added` / `### Changed` / `### Fixed`; collect unreleased entries under `## Unreleased`.
- Versions follow semver; tag releases as `vX.Y.Z`.
