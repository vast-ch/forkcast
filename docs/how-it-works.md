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
split by continent and kept compact.

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

1. **On start:** the code, `manifest.json` (the continents and their preset routes, a few kB), `world.json` (one outline per continent, ~120 kB) and Europe's climate grid and borders (1.2 MB gzipped). The app opens straight on the planner; there is no separate start page.
2. **When another continent is clicked on the map:** its climate grid (`climate.bin` + `climate.json`) and borders (`countries.json`), 0.7 to 4.8 MB gzipped, added to what is already shown. Continents not shown yet are drawn from `world.json` as light, clickable shapes.

Continents add up rather than replace each other, because a trip can cross from one to another (Europe into Asia, say). They are all cut from the same worldwide grid, so where two overlap their values are identical: `ClimateSet` in `web/app/utils/climate.ts` answers each point from the first loaded continent that covers it, and the map draws overlapping cells only once (rain dots are grouped on the worldwide grid so the patterns line up).
3. **When a route is picked:** that route's full track (`routes/<id>.json`). Every other preset route is drawn dashed from `routes/overview.json` (all routes simplified to ~1 km, 64 kB gzipped, loaded at start), so the map shows what is available without downloading each track; clicking a dashed route selects it.

Every data file is imported through `web/app/utils/assets.ts`, so the
production build gives it a content-hashed name (`climate-BRovctLk.bin`). nginx
serves everything under `/assets/` with `Cache-Control: max-age=31536000,
immutable` and `index.html` with `no-cache`.

**Why:** a changed file gets a new name, so browsers can keep files for a year without ever showing stale data, and a new release is picked up as soon as the page itself reloads. Only the continent you use is downloaded. Europe is preloaded because the preset routes are there; anyone else is one click away from their own continent.

## Settings live in the URL

Every setting (continent, month, layers, rainy-day threshold, route, start date, km per day, average speed, ride/rest pattern, direction, highlighted day) is a query parameter of the app's single planner route (`/`). `web/app/controllers/index.ts` declares them with
their defaults (`web/app/utils/settings.ts`); Ember writes a parameter to the
URL only while it differs from its default. Your own drawn or imported routes are not in the URL: they're kept whole in the browser's localStorage (`web/app/services/my-routes.ts`; everything stored is a `@stored` property, `web/app/utils/stored.ts`, polyline-encoded with elevation, plus a drawn route's clicks so it can be drawn further), and `route` holds one's random UUID. A link to a UUID this browser doesn't have shows a warning instead (`PlannerService.isMissingRoute`). Where you left off is kept in localStorage too (`web/app/services/last-visit.ts`): the whole query string after every settings change (so a new setting needs nothing extra), and the map's centre and zoom after every move. Opening the planner with no query parameters at all restores the saved query string (`IndexRoute.redirect`) and the map takes the saved view instead of fitting the route (`isResuming`); a link with any setting in it is taken as it is, fits its route, and becomes the new last visit. The view stays out of the URL: it would rewrite the address on every drag, and a view chosen on one screen doesn't suit another. Old links that carried the route itself (`track`, `name`) are saved to your routes on opening and rewritten to point at it (`IndexRoute.redirect`). The shown continents are a query parameter rather than a path (`/?continents=europe,asia`, left out when it is just Europe): changing it re-runs the route's model hook, which loads what is missing. The map's time of year is a quarter-month (`week`, 1–48, see `web/app/utils/weeks.ts`), defaulting to the current one, and the trip starts today unless the link says otherwise (a link without a start date plans from the day it is opened); quarter-months keep the familiar month grid and line up with the monthly data. In the sidebar it is a range slider with 48 steps (Frontile's `Input` with `@type="range"`, so it gets the same label and accessibility wiring as the other fields; its text-field classes are overridden and the track and thumb are styled in `app.css`). The chosen week is named above the thumb, a tick marks the start of each month and the months are labelled under the track; the arrow keys step a week. Moving it also moves the day chart: the selected day stays if it is in that week, otherwise the trip's first day in it is picked (`PlannerService.selectWeek`). A week the trip does not reach parks in a Before or After column at the ends of the day chart, by whichever end of the trip is nearer in the year (`PlannerService.offTrip`). The other way round, picking a day shows its week.

**Why:** a bookmark or a shared link reopens exactly the same plan, reloads
lose nothing, and there is no account or storage to manage. Defaults are left
out so links stay short. The rule behind this is privacy, not the address bar
as such: nothing about a plan ever reaches a server (there is none, only
static files). The URL is the natural home for a plan you want to share;
browser storage is fine for anything that can't or shouldn't go there, as
long as it stays on the device.

## Phones

Below 900 px wide (`web/app/services/media.ts`) the planner switches layout
instead of squeezing the sidebar: a slim bar (logo, continent, help, Settings),
the map, then the trip (day chart, then summary). All settings (route,
trip, map) live in a Frontile Drawer opened from the bar; it is the same `SidePanel` component rendering only its settings part, which also says which continent is loaded. Tapping the route
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
- **Rain layer:** one dot per grid cell, its area proportional to the rain or
  rainy days at that time of year (the legend gives them for the week shown), drawn as metre-sized circles on a canvas. When zoomed
  out, neighbouring cells are merged into one dot so they stay readable
  instead of turning into a striped pattern.
- **Map details,** each a toggle (Frontile `ButtonGroup` of `ToggleButton`s)
  and a URL setting (`borders`, `cities`, `relief`, `water`, `routes`):
  - **Routes** shows or hides the dashed preset routes other than the
    selected one (already loaded at start, from `routes/overview.json`).
  - **Borders** only shows or hides the country outlines; the country file
    always loads, because it also draws the land.
  - **Cities** (town names and mountain ranges) and **Water** (rivers, lakes)
    come in small per-continent files (`places.json`, `water.json`, Europe 14
    and 29 kB gzipped) that `AtlasService.loadDetail` fetches the first time
    the layer is on, never while it's off. Names show at every zoom: the
    toggles, not the zoom, decide how busy the map is.
  - **Relief** needs no file: hillshading from the terrain height already in
    the climate grid (`reliefRaster` in `web/app/utils/layers.ts`), lit from the
    north-west, slopes exaggerated ×10 since the cells are 25 km, drawn in
    greys that the pane multiplies onto the colours below, so it only darkens.
- **The legend** is a button: a click folds it into a small chip (a bit of the
  colour scale and a rain dot) and back. Whether it is folded isn't remembered:
  the URL holds the plan, and nothing else is stored.
- The map shows **cell averages**; the altitude correction only applies to
  route points (see below), because only they have a known height.

## Climate at a point and a date

`web/app/utils/climate.ts`:

- **Between grid cells:** bilinear interpolation of the four surrounding cell
  centres. A point near the coast uses only land cells; just off the coast it
  falls back to the nearest land cell.
- **Through the year:** when a continent loads, every cell's twelve
  monthly values are turned into a smooth seasonal curve: the yearly mean plus
  three harmonics (12-, 6- and 4-month waves), 7 numbers per value instead of
  12. Rain is fitted as mm per day and rainy days as the share of days, so
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
  within two weeks appears to start over about a month. The better fix for
  rain is weekly totals and rainy-day counts computed from the daily ERA5-Land
  data at build time (the daily rain is already downloaded), smoothed lightly
  and fitted with more harmonics. That is not done yet.
- **Altitude:** when a point's height is known, high and low are shifted by the month's lapse rate (4.4–6.8 °C per 1,000 m, smaller in winter) for the difference between the point and the cell's mean height. A constant 6.5 °C/km over-warmed winter valleys; see data/README.md for the measured comparison.
- **Rainy days:** read from the counted layers (≥ 1, 5, 10 mm). The chance
  that a day is rainy is the month's rainy days divided by its length.

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
- **Rainy riding days** is the sum of the daily chances: an expected number,
  not a forecast.

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
  network is `out/<continent>/cyclenet.json` (OpenStreetMap international
  bicycle routes, every continent, see data/README.md), fetched only when drawing with
  snapping on and shown faintly meanwhile; continents without a network file
  just get straight lines.

## Where things are

| Path | What |
|---|---|
| `web/app/routes/`, `web/app/templates/` | `index` (the planner, at `/`), `help`, `changelog` (CHANGELOG.md rendered with `marked`, which loads only on that page) |
| `web/app/services/atlas.ts` | loads the manifest, continents and route tracks |
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
