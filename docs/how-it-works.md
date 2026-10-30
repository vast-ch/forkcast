# How Forkcast works, and why

Forkcast shows what the weather usually does along a bike route, day by day.
This document explains how the app is put together and the reasons behind the
main decisions. How the data is downloaded and built is in
[data/README.md](../data/README.md).

## A static site, no backend

The app is a single-page Ember app served as static files (nginx in the `web`
image). All the work happens in the browser:

- the data is prebuilt by the pipeline in `data/` and shipped as files;
- the climate is looked up and the trip is planned in JavaScript;
- nothing is stored on a server.

**Why:** there is nothing to run, scale or secure, hosting can be any static
host or CDN, and the app keeps working offline once loaded. The price is that
everything a user might look at has to be downloaded, which is why the data is
split into 10° tiles and kept compact.

## No third parties

Every file the app uses comes from its own origin: the code, the data and the
fonts (bundled from Fontsource packages in `web/app/app.ts` rather than loaded
from Google Fonts). There are no analytics, cookies or ads. The hosting
headers enforce it (`web/security-headers.conf` for nginx, `web/public/_headers`
for Netlify; keep the two in step):

- **Content Security Policy:** scripts, styles, images, fonts and requests only
  from `'self'` (plus `data:`/`blob:` images for the temperature layer and the
  GPX export, and inline styles, which Leaflet and Ember's style bindings use).
  Vite is told not to inline the data files as `data:` URLs
  (`build.assetsInlineLimit` in `web/vite.config.mjs`), since the policy only
  allows fetching from the site.
- **Referrer-Policy: no-referrer** (also a `<meta>` in `index.html`, for hosts
  without headers): the plan is in the URL, and a linked site would otherwise
  receive it.
- **Permissions-Policy: browsing-topics=()**: no interest-based ad topics from
  visits here.

**Why:** a trip plan says where someone will be and when. It should not reach
anyone the rider didn't send it to.

## What gets downloaded, and when

1. **On start:** the code, `routes/index.json` (the preset routes, under 1 kB gzipped), `routes/overview.json` (every preset route simplified to ~1 km, 64 kB), `countries.json` (the world's borders as TopoJSON, 231 kB) and the climate's header and world overview (`climate/<climate>.json` and `climate/<climate>/overview.bin`: the whole world at 1°, 530 kB). The app opens straight on the planner, on Europe; there is no separate start page.
2. **As the map is zoomed in, and along the route:** from zoom 5 on (a country or two in view) the map draws from the 0.25° tiles in view (`climate/<climate>/<lat>_<lon>.bin`, 10° squares, 25–40 kB gzipped each, only where there is land), fetching each as it comes into view; zoomed out it draws from the overview. The trip always uses the tiles its route crosses: they load with the route, and until they're in, the overview answers. Picking another climate (last 10 or 5 years, 2025, El Niño, La Niña) loads its overview and the same tiles of it.

A tile holds 41 × 41 cells: its edges' cells are also in its neighbours, so any point in it is interpolated from that tile alone, without seams. `TiledClimate` in `web/app/utils/climate.ts` answers each point from its tile if loaded, else from the overview; the map draws each tile's own square, and rain emoji and dots are grouped on the worldwide grid so the patterns line up across tiles.

**Why tiles, not continents:** a rider downloads what they look at and ride through, not a whole continent, and nothing has to be picked first. Asking for tiles does tell the static host which 10° squares were looked at; the help's privacy section says so.
3. **When a route is picked:** that route's full track (`routes/<id>.json`). Every other preset route is drawn dashed from `routes/overview.json` (all routes simplified to ~1 km, 64 kB gzipped, loaded at start), so the map shows what is available without downloading each track; clicking a dashed route selects it.

Every data file is imported through `web/app/utils/assets.ts`, so the
production build gives it a content-hashed name (`climate-BRovctLk.bin`). nginx
serves everything under `/assets/` with `Cache-Control: max-age=31536000,
immutable` and `index.html` with `no-cache`.

**Why:** a changed file gets a new name, so browsers can keep files for a year without ever showing stale data, and a new release is picked up as soon as the page itself reloads. The list of every hashed name is part of the code: about 1,600 files, 19 kB gzipped.

## Settings live in the URL

Every setting (climate, month, layers, rainy-day threshold, route, start date, km per day, average speed, ride/rest pattern, direction, highlighted day) is a query parameter of the app's single planner route (`/`), with one name everywhere: the URL parameter, the controller field and the planner property are the same (`kmPerDay`, `cities`, `highlightedDay`…), and so are their values. `web/app/controllers/index.ts` declares them with
their defaults (`web/app/utils/settings.ts`); Ember writes a parameter to the
URL only while it differs from its default. Your own drawn or imported routes are not in the URL: they're kept whole in the browser's localStorage (`web/app/services/my-routes.ts`; everything stored is a `@stored` property, `web/app/utils/stored.ts`, polyline-encoded with elevation, plus a drawn route's clicks so it can be drawn further), and `routeId` holds one's random UUID. A link to a UUID this browser doesn't have shows a warning instead (`PlannerService.isMissingRoute`). Where you left off is kept in localStorage too (`web/app/services/last-visit.ts`): the whole query string after every settings change (so a new setting needs nothing extra), and the map's centre and zoom after every move. Opening the planner with no query parameters at all restores the saved query string (`IndexRoute.redirect`) and the map takes the saved view instead of fitting the route (`isResuming`); a link with any setting in it is taken as it is, fits its route, and becomes the new last visit. The view stays out of the URL: it would rewrite the address on every drag, and a view chosen on one screen doesn't suit another. The map's time of year is a quarter-month (`week`, 0–47, see `web/app/utils/weeks.ts`), defaulting to the current one, and the trip starts today unless the link says otherwise (a link without a start date plans from the day it is opened); the start date's calendar colours each day by the temperature at the route's first point on that date (`PlannerService.startTempOn`, the map's high or low), through `TempCalendar`, Frontile's `Calendar` with a `<:day>` block, which the help's demo shares; quarter-months keep the familiar month grid and line up with the monthly data. In the sidebar it is a range slider with 48 steps (Frontile's `Input` with `@type="range"`, so it gets the same label and accessibility wiring as the other fields; its text-field classes are overridden and the track and thumb are styled in `app.css`). The chosen week is named above the thumb, a tick marks the start of each month and the months are labelled under the track; the arrow keys step a week. Moving it also moves the day chart: the selected day stays if it is in that week, otherwise the trip's first day in it is picked (`PlannerService.selectWeek`). A week the trip does not reach parks in a Before or After column at the ends of the day chart, by whichever end of the trip is nearer in the year (`PlannerService.offTrip`). The other way round, picking a day shows its week.

**Why:** a bookmark or a shared link reopens exactly the same plan, reloads
lose nothing, and there is no account or storage to manage. Defaults are left
out so links stay short. The rule behind this is privacy, not the address bar
as such: nothing about a plan ever reaches a server (there is none, only
static files). The URL is the natural home for a plan you want to share;
browser storage is fine for anything that can't or shouldn't go there, as
long as it stays on the device.

## Phones

Below 900 px wide (`web/app/services/media.ts`) the planner switches layout
instead of squeezing the sidebar: a slim bar (logo, help, Settings),
the map, then the trip (day chart, then summary). All settings (route,
trip, map) live in a Frontile Drawer opened from the bar; it is the same `SidePanel` component rendering only its settings part. Tapping the route
selects a day: touch screens have no hover, so the map works out what is under
the tap before handling it. Drawing a route closes the drawer and shows a
floating toolbar on the map (points, Undo, Save, Cancel).

On every screen the map's attribution is one short line, "© OpenStreetMap ·
EuroVelo · Credits": the notices the route data's licences (ODbL) want next to
the map, and a link to the help page's sources, where every credit and licence
is written out in full. A longer line covered the map, on phones most of all.

**Why:** on a phone the map and the day-by-day weather are what you look at;
the settings are changed now and then. Leaflet's own z-indexes are contained
(`isolation: isolate` on the map's section) so the drawer and the bar stay on
top.

## The day chart

Under the map, one column per day: the day number on top, a bar from the night low to the day high, coloured by the high, the chance of a rainy day under it. Rest days are shaded columns, with the weather at the rest stop, and a line, labelled with the month's name along it, marks the start of each month; the selected day's date is above the chart. It is the one place to pick a day (there is no separate day list): click a column, or focus the chart and step through the days with the arrow keys (Home and End jump to the ends). For screen readers the chart is a slider whose value is the selected day with its distance and weather; the drawing itself is hidden from them.

**Why:** a list of days repeated what the chart shows, and on a phone it was a long scroll. The selected day's figures sit above the chart.

## The map

- **Leaflet** with our own basemap: country outlines from Natural Earth
  drawn as vectors. No tile server, so no third-party requests and no keys.
- **Temperature layer:** the climate grid is regular in latitude, the map
  (Web Mercator) is not, so the layer is rendered into a canvas row by row in
  Mercator coordinates rather than stretching an image; otherwise it would
  drift off the coastlines towards the poles.
- **Rain layer:** by default rainy days a week as emoji (`rainMarks` in
  `web/app/utils/layers.ts`): fewer than one shows nothing, then 🌦️, 🌧️
  and ☔, each a little bigger, at steps that depend on the rainy-day
  threshold (`EMOJI_STEPS`): 1–2–3 a week for 1 mm, 1–1½–2 for 5 mm, 1–1½
  for 10 mm. Fixed steps of 1–2–4 left 5 mm (the default) with a ☔ nowhere
  in Europe in any month and 🌧️ on 4% of land. With these, ☔ covers about
  26% of land at 1 mm (any rain is common), 4% at 5 mm, and 🌧️ 1% at 10 mm
  (heavy-rain days are rare, so that map stays mostly clear). The dots it replaced as the
  default sized every cell, so the whole map was speckled and a new rider had
  to read area as amount; tiers that start at one rainy day leave dry regions
  empty and say "wet week" at a glance. The emoji are text drawn into canvas
  tiles (an `L.GridLayer`), so thousands stay cheap and keep their pixel size
  at every zoom. "A week" is 7 days at the rate of the quarter-month shown
  (the climate is a smooth seasonal curve, sampled at the slot's middle).
  The other option, mm, is one dot per grid cell, its area proportional to
  the rain at that time of year (the legend gives it for the week shown),
  drawn as metre-sized circles on a canvas. Either way, when zoomed out,
  neighbouring cells are merged into one so they stay readable instead of
  turning into a striped pattern.
- **City names** are a choice rather than a toggle (URL setting `cities`:
  `top10`, the default, `big` or `off`): the 10 biggest towns per country, or every town over 500,000. A
  region-wide top 10 would leave most countries blank, and a fixed size
  limit alone either floods the map or empties small countries, so both are
  offered. `places.json` carries each town's population and its rank in its
  country, ranked over the whole world. Zoom has one breakpoint, the same
  for every setting: below zoom 6 (a few countries or more in view) only capitals keep
  their names; closer in, the chosen set shows (`isPlaceShown` in
  `web/app/utils/layers.ts`). Capitals show with every setting but off, even
  under 500,000 (Bern), so none disappears as you zoom in. There are no
  mountain-range names: they cluttered the map without helping plan a ride,
  and the relief shading shows where the mountains are.
- **Map details,** each a toggle (Frontile `ButtonGroup` of `ToggleButton`s)
  and a URL setting (`borders`, `relief`, `water`, `routes`):
  - **Routes** shows or hides the dashed preset routes other than the
    selected one (already loaded at start, from `routes/overview.json`).
  - **Borders** only shows or hides the country outlines; the country file
    always loads, because it also draws the land.
  - **Water** (rivers, lakes), like the city names, comes in a world file (`water.json`, `places.json`,
    190 and 76 kB gzipped) that `AtlasService.loadDetail` fetches the first
    time the layer is on, never while it's off.
  - **Relief** needs no file: hillshading from the terrain height already in
    the climate grid (`reliefRaster` in `web/app/utils/layers.ts`), lit from the
    north-west, slopes exaggerated ×10 since the cells are 25 km, drawn in
    greys that the pane multiplies onto the colours below, so it only darkens.
- **Dates on the route** (URL setting `dates`: `months`, the default,
  `weeks` or `off`): a tag over the night stop of the 1st of each month
  ("Nov") or of the first day of each week of the trip ("Week 2");
  `milestones` in `web/app/utils/itinerary.ts`. The tag marks where the
  rider is at that moment, so a rest day on the 1st isn't moved to the next
  day ridden: it sits on the stop where the rider rests. The trip's start has
  no tag of its own unless it falls on a 1st. Only where a period begins, not
  every stop, so a long trip stays readable at any zoom.
  They're in the labels pane, above the stops, and never take the pointer, so
  a stop's own tooltip and click still work.
- **The legend** is a button: a click folds it into a small chip (a bit of the
  colour scale and a rain emoji or dot) and back. Whether it is folded isn't remembered:
  the URL holds the plan, and nothing else is stored.
- The map shows **cell averages**; the altitude correction only applies to
  route points (see below), because only they have a known height.

## Climate at a point and a date

`web/app/utils/climate.ts`:

- **Which climate:** the `climate` setting (in the URL like every other)
  picks the grids: the 2011–2025 average, the last 10 or 5 years, 2025 alone,
  El Niño or La Niña. They share one format, so everything below works the same on each.
  `app/services/atlas.ts` loads each tile of each climate once and keeps it,
  so switching back is instant. How they're made: `data/README.md`, "Climate
  variants".
- **Between grid cells:** bilinear interpolation of the four surrounding cell
  centres. A point near the coast uses only land cells; just off the coast it
  falls back to the nearest land cell.
- **Through the year:** every cell's twelve monthly values are turned into a
  smooth seasonal curve: the yearly mean plus three harmonics (12-, 6- and
  4-month waves), 7 numbers per value instead of 12 (3 for how far days
  stray: the mean and the yearly wave). The data build does the
  fit and publishes the 7 numbers (`data/forkcast_data/pack.py`; precision
  and size in data/README.md), so the app only evaluates the curves. Rain is fitted as mm per day and rainy days as the share of days, so
  months of different lengths compare fairly; results are clamped to
  0 … 1 / ≥ 0. A monthly average flattens each wave a little compared with
  its value at mid-month (by sin(πk/12)/(πk/12) for the k-th wave), so the
  fitted waves are scaled back up by that factor; otherwise peaks would come
  out too mild. Any day of the year then has its own value (`ClimateGrid.at`).
  The previous version blended linearly between mid-month values, which left
  kinks every month in the trip and whole-month steps on the map.
- **Why curves and not weekly tables:** 52 weekly layers would make every
  download about four times bigger, and the temperatures would not be more
  real for it: the only fast temperature source is monthly (see
  data/README.md). The curves cost nothing to download and make every value
  continuous.
- **The trade-off:** the curve cannot change faster than its shortest wave
  (4 months), so sharp seasonal edges are softened; a monsoon that starts
  within two weeks appears to start over about a month. Curves fitted to the
  daily ERA5-Land rain with more harmonics look sharper, but measured on
  years left out of the fit they predict worse, not better (data/README.md,
  "Seasonal curves, packed at build").
- **Altitude:** when a point's height is known, high and low are shifted by the month's lapse rate (4.4–6.8 °C per 1,000 m, smaller in winter) for the difference between the point and the cell's mean height. A constant 6.5 °C/km over-warmed winter valleys; see data/README.md for the measured comparison.
- **Rainy days:** read from the counted layers (≥ 1, 5, 10 mm), whose
  curves are the share of days that rainy: the chance that a day is rainy.
- **Rain when it rains:** the day's mean rain divided by the share of days with at least
  1 mm (the standard "simple daily intensity"), whatever the rainy-day
  threshold: an average spread over the dry days too can't tell a daily
  drizzle from a fortnightly downpour. Left out where fewer than one day in
  50 has rain.

## Planning the trip

`web/app/utils/itinerary.ts`:

- The route is cut into equal stretches of the daily distance; ride and rest
  days follow the repeating pattern (ride N, rest M). A trip never ends on a
  rest day.
- **A day's high and rain** are taken at the middle of its stretch: that is
  where you spend most of the riding hours. **The night low** is taken at the
  end of the stretch, where you sleep, because that is the night you feel.
- **Climbing** sums every ascent along the stretch from the track's elevation.
- **Daylight** (`web/app/utils/sun.ts`) is sunrise at the start of the stretch to sunset at its end, from the sunrise equation NOAA's solar calculator uses (within a minute or two). Both are absolute times, so the difference needs no time zones, which is why the app shows the duration rather than clock times: those would need each place's time zone (Spain, for one, keeps Central European time west of Greenwich). Midnight sun counts as 24 h, polar night as none.
- **Usual ranges:** each day's high and low come with how far single days
  stray from them there and then (`highSpread`, `lowSpread`: a standard
  deviation, measured on NOAA CPC's station data; data/README.md, "How far
  single days stray"). "Usually" is where 8 days in 10 fall, mean ± 1.28
  spreads (`usualRange`); the day chart draws it as a faint band behind each
  bar, from the usual warmest high to the usual coldest low.
- **Coldest night, likely** and **hottest day, likely** (`likelyExtreme`):
  the value the trip's coldest night (hottest riding day) is as likely to
  beat as not, each night (day) normal with its mean and spread. Nights are
  not independent tries, since cold comes in spells: counted as one try per 2
  nights and per 2.5 days (`EXTREME_SPELL`), measured on CPC's 2011–2025 days
  at 1,200 places for trips of 7–60 days. With every night counted, the real
  coldest night came out below the estimate in only 21–32% of trips; with
  these, 47–51% (the hottest day above it 40–58%).
- **Coldest average night** is the lowest of the nights' mean lows, and its
  date: when the cold is likeliest, while the likely coldest night says how
  cold.
- **Rainy riding days** is the sum of the daily chances: an expected number,
  not a forecast. Its range (`rainyDaysRange`) is where 8 trips out of 10
  fall: the count taken as beta-binomial, with the spread widened from what
  independent days would give, because rain comes in spells. How much wider
  was measured on the daily ERA5-Land rain, 2011–2025: across land, the
  number of rainy days in a week to two months varies from year to year
  about 2× as much (variance) as independent days would at 1 mm, 1.6× at
  5 mm and 1.5× at 10 mm (medians; the middle half of places 1.4–2.7× at
  1 mm). That is for one place; a trip moves on, but at a day's ride it
  stays within the same weather systems.

## Routes

- **EuroVelo:** the official GPX tracks contain variants (both banks of a
  river, alternatives through different countries) and spurs. Riding all of
  them would roughly double some routes, so stages form a network and the
  route is the shortest path from start to finish. Holes between stages are
  bridged: over the sea as ferries (travel time, not riding distance), over
  land as unmapped stretches (counted).
- **Demo route:** a list of towns routed with BRouter's touring profile, so
  distances and climbing are real.
- **Your own routes:** drawn or imported from GPX, as many as you like, each
  with a name; drawn routes have no elevation.
  While drawing, the clicks are a sketch (`PlannerService.sketch`). With "Follow
  cycle routes" on (the default, `snapToRoutes`) the route is the cycle-network
  line for it (`CycleNet.match` in `web/app/utils/cyclenet.ts`): each click is
  snapped onto the nearest network line within 25 km (a grid of segments),
  and consecutive clicks are joined by the shortest way along the network (A*
  on distance); more clicks steer it. A click with no line near stays put, and
  a join that isn't connected or would be a detour (over 3× the straight
  distance) is straight. Off, the clicks are joined with straight lines. The map
  shows the sketch dashed under the result; Undo removes the last click. The
  network is `out/cyclenet.json` (OpenStreetMap international bicycle routes,
  the whole world, see data/README.md), fetched only when drawing with
  snapping on and shown faintly meanwhile; where there is no network, the
  clicks get straight lines.

## Where things are

| Path | What |
|---|---|
| `web/app/routes/`, `web/app/templates/` | `index` (the planner, at `/`), `help`, `changelog` (CHANGELOG.md rendered with `marked`, which loads only on that page) |
| `web/app/services/atlas.ts` | loads the route list, borders, climate tiles and route tracks |
| `web/app/services/planner.ts` | all planner state, read from and written to the URL |
| `web/app/components/wheel-map.gts` | the Leaflet map |
| `web/app/utils/` | climate sampling, trip planning, route geometry, map layers |
| `data/forkcast_data/` | the data pipeline ([data/README.md](../data/README.md)) |

## Known limits

- Climate normals describe a typical year; any given week can differ a lot.
- 0.25° cells (≈ 25 km) still blur narrow coasts; the altitude correction
  helps route points in mountains but not, for example, a seafront town whose
  cell includes hills at the same height.
- Winter in Alpine valleys reads 2–3 °C too mild, nights more (cold-air pooling, fog).
- The demo route and EuroVelo tracks are simplified (≈ 30–40 m tolerance),
  which slightly understates climbing.
