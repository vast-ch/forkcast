# Changelog

## Unreleased

### Added

- Nerd mode for the help: a switch at the top shows, on every page, how each number is made and how well it holds up, measured against what the weather really did: does the usual range really hold 8 days in 10, do half of real trips beat the likely lowest low, which climate would have planned a trip best over 30 years, how much a month swings from year to year, and more. Nothing in it is a guess: each figure comes from tests run on the data, with how sure it is.
- Choose the climate: the map and your trip can also use only the last 10 or 5 years (to see how much warmer it has become), or a year with El Niño or La Niña. Forecasters see those coming months ahead, so if your trip falls in one, you can plan for what it tends to bring: a drier spring in eastern Australia, a milder winter in western Canada and more. The help's new Climates page explains each and where they matter (in Europe, El Niño and La Niña hardly change anything).
- A one-year climate, “1 yr”: see your trip in 2025, a real year, each month as it actually was, rather than the average. Spain's record-hot June is in it, and every unusually wet or dry month. One year is one roll of the dice, so it shows what can happen rather than what to expect.
- Each day's high and low now come with their usual range, in brackets, such as “(9 to 20°C)”: where 8 days in 10 fall, measured from weather stations for that place and time of year. The day chart shows it as a thin line through each day's bar. A coast in summer barely varies; a continental winter can swing 15°C.
- The trip summary says how low your lowest low and how high your highest high are likely to be: half of trips get lower or higher, the rest milder. Cold and heat come in spells, and that is counted in. Before, the summary only had the lowest *average* low, which real trips nearly always beat.
- An About page in the help: who makes Forkcast, where to report a problem or ask for a feature, and a QR code to our Discord channel.
- The start date's calendar is coloured by the weather: each day shows, in the map's colours, how warm it usually is where your route begins if you set off that day, so a good time to leave stands out at a glance. The help's “Your trip” page lets you try it for a few starting towns.

### Changed

- A day of your trip, and a spot on the map, now say how much rain a day brings when it rains, instead of an average over all days. An average of 1 mm a day can be a drizzle every day or a downpour once a fortnight; now you can tell which.
- Temperatures are just the high and the low, everywhere: the map's switch, a day of your trip, the summary and the help. The low is where you sleep, the high where you ride; together they span the day and night you camp through.
- Rainy riding days in the trip summary now come with a range, e.g. "9 (6–12)": how many 8 trips out of 10 get. Rain comes in spells, so some trips catch a lot more than the average and some a lot less.
- The map's climate data is half the size, so it downloads about twice as fast, with the same temperatures and rain, give or take a few tenths of a degree.
- The whole world is on the map, in 10° squares: no more clicking a continent to add it. The squares your route crosses load by themselves; any other square is outlined, and a click loads its climate, a few dozen kB. Forkcast remembers the squares you loaded, so you download only the parts of the world you ask for. The help's privacy section explains what this means for what our host can see.
- Pop-up calendars now have a clear edge and shadow, so they stand out from the panel behind them.

### Fixed

- The Discord link and QR code on the About page now work for everyone, not only for people already in our Discord: they open an invite to the Forkcast channel.

## v0.13.0 - 2026-10-27

### Changed

- City names on the map are now a choice instead of a long fixed list: the 10 biggest towns in each country (the new default, a much calmer map), every town of over 500,000 people, or none. Until you zoom in on a region, only the capitals keep their names, so the map stays readable.
- The names of mountain ranges are gone from the map; the relief shading shows where the mountains are.

## v0.12.0 - 2026-10-27

### Added

- Dates on the map: tags over your route show where you'll be on the 1st of each month ("Nov"), or, if you switch to weeks, at the start of each week of the trip ("Week 2"). Switch them off under "Dates on the route".

### Changed

- The selected night stop on the map is now purple, like the selected day everywhere else in Forkcast; the other stops are ringed in dark grey, so the one you picked stands out.
- Rain on the map is calmer and easier to read. By default it now shows how many rainy days a typical week brings: 🌦️, 🌧️ or ☔ as it gets wetter, and nothing where it's less than one, so dry regions stay clear instead of speckled with dots. What counts as a rainy day (1, 5 or 10 mm) is still your choice, and the steps follow it, since heavy rain is rarer: with the usual 5 mm, ☔ means 2 or more rainy days a week. The amount in mm, as dots, is one click away.

## v0.11.0 - 2026-10-25

### Added

- A "What's new" page, linked from the help page, lists every release and what it changed.
- Forkcast remembers where you left off. Open it again without a link and your last plan is back, with the map where you left it; a link still opens exactly the plan it carries.

## v0.10.0 - 2026-10-24

### Added

- Keep as many routes of your own as you like. Every route you draw or import is saved under "Your routes" in the list and shows dashed on the map; each has a name, given as you draw it and changed with "Edit route", which also takes a drawn route back into drawing to extend or reshape it, with the day chart and the trip following every click; each can be deleted on its own.

### Changed

- Your own routes are now kept whole in your browser instead of in the page address, so long GPX tracks keep every bend and their true length (the address could only hold a smoothed, shorter copy). A link to one of your routes only names it, so it opens where you made it; to share a route, send its GPX file. Old links that carried a route still open, and save it to your routes.
- The help's privacy part says plainly what matters: nothing about you, your plan or your routes goes to a server.
- Drawing and editing a route look the same on phones and computers: the route's name, "Follow cycle routes", Save route, Undo and Cancel.

### Fixed

- On phones and in narrow browser windows the trip summary (days, arrival, riding and rest days, average high, rainy days, coldest night) was cut off under the day chart and couldn't be scrolled to. It now sits with the trip settings in the Settings drawer, where it belongs, and the page under the map scrolls again.
- Leaving the map for the help page while it was still zooming caused an error behind the scenes.

## v0.9.0 - 2026-10-24

### Added

- Drawing a route now follows the international cycle routes in Europe, Africa and Asia (in Europe, the EuroVelo routes). The other continents follow with the next data update.

### Changed

- Drawing a route is quieter: just the "Follow cycle routes" switch and the Save, Undo and Cancel buttons, without instructions or a name to fill in (a drawn route is called "My route"). The help's Routes tab explains drawing.
- The help page is rewritten and split into tabs (Map, Trip, Routes, Data, Accuracy, Sharing & privacy, Sources), one topic at a time, each with its own address to link to. It now explains the day chart, a day's numbers, daylight and the 🔦, and the trip summary, and has live parts to try: the temperature colours, the map legend, a daylight-and-riding-time calculator and the altitude correction. The map's Credits link opens Sources directly.
- The help page's sources and licences now also credit the cycle routes used for drawing (OpenStreetMap, shared under the ODbL) and say where the relief shading comes from.

## v0.8.0 - 2026-10-24

### Added

- Drawing a route can follow the cycle routes: each click moves onto the nearest international or national cycle route, and the route follows the cycle routes from one click to the next, going straight only where there are none. Add clicks to steer it. Switch "Follow cycle routes" off for straight lines; the sketch stays on the map either way, and Undo takes back the last click. The cycle routes to follow arrive with the next data update; until then drawing gives straight lines.
- A Routes button under Map shows or hides the dashed routes you haven't picked, for a cleaner map; the route you're on always stays.

## v0.7.1 - 2026-10-24

### Changed

- The rainy-day setting reads "Rainy day  > 1mm 5mm 10mm", with the sign next to the amounts it belongs to.

### Fixed

- Double-clicking the map zooms in again. Only while you draw a route does a double-click finish the route instead.
- On the map the route and the picked day's purple stretch run under the overnight stops instead of over them, so every stop's ring stays whole.

## v0.7.0 - 2026-10-24

### Added

- The map can show more: country borders, city and mountain-range names, relief shading and rivers and lakes, each switched on and off with buttons under Map. Names and water are only downloaded once you switch them on.

### Changed

- Temperatures for a day and for a spot on the map sit in pills coloured like the map and the chart, so a cold night or a hot afternoon stands out at a glance.

### Fixed

- With both temperature and rain switched off, the map no longer shows an empty legend box.

## v0.6.1 - 2026-10-24

### Changed

- A day's temperatures read Low, then High, both above the chart and on the route, instead of High and Night.

### Fixed

- On phones the Draw a route, Import GPX and Export GPX buttons sit one under the other instead of squeezing their labels onto two lines.

## v0.6.0 - 2026-10-24

### Added

- Click the map's legend to fold it into a small chip, and click again to bring it back.

### Changed

- The start date is picked from a calendar that looks the same in every browser, with weeks starting on Monday, instead of the browser's own date field.

### Fixed

- On phones the map's legend fits on one line again: a narrower colour scale, with every temperature mark including 0 and the °C written once, after the last.

## v0.5.0 - 2026-10-24

### Added

- Each day shows its hours of daylight, from sunrise where you start to sunset where you stop, when you pick it in the chart or point at it on the route. In the far north it says when it's the midnight sun or the polar night.
- A new trip setting, average speed (21km/h by default), turns each day's distance into riding time, shown with the day you pick and on the route. Compare it with the day's daylight to see whether a day is realistic.
- A 🔦 marks every day in the chart whose riding time is longer than its daylight, so you can see which days you'd ride partly in the dark.

### Changed

- Forkcast no longer talks to anyone but its own site. The fonts are part of the app instead of coming from Google, your browser is told to refuse anything from elsewhere, and following a link out of the app no longer passes your plan along. There is no tracking of any kind; the help page has a short Privacy section.
- Units sit right next to their numbers (80km, 4.9mm, 657m, 9h 42min), and temperatures say °C so there's no doubt about the scale.
- The credits along the bottom of the map are down to one short line with a link to the full list on the help page, so they no longer cover the map.
- The map's legend is just the colour scale and the rain dots, without the titles over them; the sidebar already says what's shown.

## v0.4.0 - 2026-10-23

### Changed

- Moving the week on the map now moves the day chart with it: it picks your trip's first day in that week. A week outside the trip is shown in a "Before" or "After" column at either end of the chart, whichever end of the trip it is nearer to.
- The sidebar's "Climate on the map" section is now called "Map" and comes last, after Route and Trip.
- The line in the day chart where a new month starts is labelled with the month's full name, written along it.

## v0.3.0 - 2026-10-23

### Changed

- Rest days in the day chart show their temperatures and chance of rain too, for where you stay; they are still the shaded columns.
- A new logo: a bicycle wheel rising over the horizon like the sun, in the top left, as the browser tab icon and as the home-screen icon.
- The day list is gone: the chart under the map now shows each day's number along its top (rest days included, in place of the old "R") instead of dates under it, and you pick a day there, by clicking or with the arrow keys. The selected day's distance, climbing and weather appear above the chart.
- A new trip starts today instead of on 1 January.
- Picking a start date selects the trip's first day, so the chart, the map and its week start there.
- Clicking an overnight stop on the map now also moves the map to that day's week, as picking the day in the chart or the list already did.
- The overnight stops along your route have a glowing purple ring, and the day you pick is the same purple on the map (its stretch) and in the day chart (its column), so it stands out on every temperature colour.

### Fixed

- Rain on the map is now given for the week shown, like the temperatures: in the readout when you point at the map, and in the legend ("Rain per week", "Days with 5 mm or more per week"). They used to be monthly figures under a weekly heading, so a week could show more than 7 rainy days.

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
