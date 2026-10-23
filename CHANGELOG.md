# Changelog

## Unreleased

### Changed

- A new trip starts today instead of on 1 January.
- The overnight stops along your route have a glowing purple ring, so they stand out on every temperature colour.

## v0.2.0 - 2026-10-23

### Added

- All preset routes are shown on the map as dashed lines; point at one to see its name, click it to plan it.
- Better climate data: Forkcast now uses ERA5-Land from the European Copernicus programme, on a grid twice as fine (about 25 km). Rainy days are now counted from daily rain instead of estimated, and highs and lows are matched to weather-station measurements.
- Temperatures along your route are corrected for altitude: a valley town or a mountain pass gets its own temperature instead of its area's average, with a smaller correction in winter, when cold air settles in valleys.
- A new name and look: Wheelther is now **Forkcast**, with a logo (a bike fork with the sun between its legs) in the top left and as the browser tab icon.
- The help page now explains where the weather data comes from, how each number is calculated, and how far to trust it, with real figures for how much the weather varies from year to year.
- The whole world. Forkcast opens straight on the map of Europe for the current month; every other continent is shown in its own colour, and clicking it adds its climate (a one-off download of 1–5 MB). Show as many as your trip crosses.
- Every setting is kept in the page address: month, layers, route, start date, distances, ride and rest days, the rainy-day threshold, the highlighted day, and your own drawn or imported route. Bookmark or share the link and the same plan opens again. Settings left at their defaults stay out of the address.

### Changed

- The weather now changes smoothly through the year instead of jumping from one month to the next: every day of your trip gets its own value, and the map shows any week. Choose the week with a slider: drag it through the year, or step a week at a time with the arrow keys. The smoothing softens very sudden seasonal changes, like the start of a monsoon; the help page explains this trade-off.
- On phones, Forkcast now has its own layout: the map first, then your trip day by day, with every setting in a Settings drawer. Tapping the route picks that day, and drawing a route works with a small toolbar on the map.
- The rain bars under the day chart are now labelled: they show the chance of a rainy day (over your chosen amount), on a 0–100 % scale.
- "Ride it the other way" is now a small button with up-down arrows next to the route picker.
- The link to the help page is now a question-mark icon in the top corner.
- On phones, the trip summary under the day chart no longer repeats a "Trip" heading.
- The "Ride 5 days, rest 1 day, repeat" line under the trip settings is gone; the ride and rest fields say it already.
- The trip summary is tidier: one number per item, with riding and rest days and the date of the coldest night as items of their own.
- The panel's section headings (climate on the map, route, trip, day by day) are full-width shaded bands, so it is clearer where one section ends and the next begins.
- The trip summary's values are all in one typeface, so the arrival date no longer looks out of place next to the numbers.
- Draw a route, Import GPX and Export GPX now look the same and share the full width of the panel.
- Days are simply the route cut into equal stretches of your daily distance; the nearby town names are gone.
- Your own route is now kept in the page address instead of in the browser, one at a time. Drawing or importing a new one replaces it.
- The app and its data now download once and are then kept by your browser for up to a year, so opening it again is fast. New releases are still picked up straight away.
- Rain dots merge into bigger ones when the map is zoomed out, so they stay readable on a whole continent.

## v0.1.0 - 2026-10-23

First version.

### Added

- A climate map of Europe and North Africa for any month: the average day high or night low as colour, with rain as dots on top, either rainfall in mm or the number of rainy days. Pointing at the map shows the averages for that spot. Data: averages of 2011–2025 from CRU TS 4.10 (University of East Anglia), on a grid of about 50 km.
- You choose how much rain makes a day rainy: over 1 mm, 5 mm (the default) or 10 mm. The climate records only count days with at least 0.1 mm, which includes a five-minute drizzle, so days over the threshold are estimated from each month's rainfall and wet days.
- All 17 EuroVelo routes, from the official EuroVelo GPX tracks, plus a demo route from Interlaken down the Rhône valley and Spain's east coast to Málaga. Pick one from the route list.
- Your own routes: draw one on the map or import a GPX file. They are saved in your browser, and any route can be exported as GPX or ridden the other way.
- A trip planner: set a start date (1 January by default), km per day, and a repeating pattern of ride days and rest days (e.g. ride 5, rest 2). Wheelther lays the route out day by day with the expected day high, night low, chance of a rainy day and climbing, and sums it up: total days, arrival date, average high, rainy riding days and the coldest night.
- Pointing at the route shows the day you would be there and that day's expected weather. A chart under the map shows every day of the trip; clicking a day, there or in the day list, highlights its stretch on the map.
- A "How it works" page explaining the data, the rainy-day estimate, how days are calculated, where the routes come from, the limits, and the sources and licences.
