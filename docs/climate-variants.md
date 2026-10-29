# Climate variants

Status: built (October 2026). The app's "Climate" setting offers the
2011–2025 average plus four variants: the last 10 years, the last 5, El Niño
and La Niña. How they are built is in `data/README.md` ("Climate variants");
this file is why: the question, the research and what it decided.

## The question

Forkcast's climate is the average of 2011–2025. Riders planning a particular
year might want a different one:

- **Recent windows**: the last 10 years (2016–2025) or the last 5 (2021–2025),
  to see how much warmer it has become.
- **Phases of climate oscillations** that can be forecast months ahead, so a
  rider can pick "2027 looks like an El Niño year": **El Niño** and
  **La Niña** (ENSO; forecast 6–9 months ahead) and the **Indian Ocean
  Dipole** (IOD; about a season ahead).

One variant at a time, never combined: combinations (El Niño with NAO−, say)
leave too few years to average, and the oscillations aren't independent (the
IOD often comes with ENSO). The NAO was left out because it can't be forecast
more than about two weeks ahead, so a rider couldn't know which phase to
pick. The AO tracks the NAO, the MJO and QBO change too quickly for a year to
have a phase, and the PDO and AMO change too slowly.

Before building any of it: would a variant change the grid enough for a rider
to notice, and would that change be real or the noise of averaging few years?

## Method

`data/forkcast_data/variants_research.py`, on the per-year fields of
`build years` (ERA5-Land highs and lows as the warmest and coldest hour of
the month's average day, monthly rain, rainy days). How to run it is in
`data/README.md`.

1. **Windows**: the window's average minus the 2011–2025 average, per cell and
   month. The warming trend stays in, since that is what a window shows.
2. **Phases**: the linear trend per cell and month is removed first, or a phase
   whose events happen to be recent would mostly show the warming. The phase
   is the average of its months' departures from that line.
3. **ENSO months** come from NOAA's Oceanic Niño Index, month by month: a
   month is El Niño (La Niña) when it lies in an event, a run of at least 5
   overlapping seasons at ≥ +0.5 °C (≤ −0.5 °C); "strong" also needs the month
   itself at ≥ 1.0 °C. Calendar years would be a poor fit: events peak around
   December and span two years.
4. **Noticeable**, per land cell and month: highs or lows moved by ≥ 0.5 °C
   (the grid's step); monthly rain by ≥ 20 % and ≥ 10 mm; ≥ 1 rainy day more or
   fewer a month.
5. **Real**: the phase's change at a cell beats 90 % of 100 random sets of as
   many years at that cell (so 10 % of cells pass by chance). A continent's
   share of real cell-months well above 10 % means a real effect.

## First attempt: 2011–2025 only

With 3–4 events of each phase in 15 years, a phase average was mostly noise:
any 4 random years moved the highs of about half of Europe's cell-months by
0.5 °C or more. Some signal showed in South America, Oceania and Africa,
none in Europe, Asia or North America. Phases needed more years, so ERA5-Land
was extended back to 1981 (30 more years, about 3.5 hours from the CDS).

## Findings over 1981–2025

About 13 events of each ENSO phase (8–16 years per calendar month).
Share of cell-months where the change is real (10 % by chance), and the mean
change of highs:

| | Europe | Africa | Asia | North America | South America | Oceania |
|---|---|---|---|---|---|---|
| El Niño, highs real | 14 % | 34 % | 21 % | 26 % | 43 % | 35 % |
| El Niño, mean highs | +0.04 °C | +0.10 °C | +0.01 °C | +0.10 °C | +0.26 °C | +0.31 °C |
| El Niño, rain real | 16 % | 24 % | 20 % | 17 % | 26 % | 26 % |
| La Niña, highs real | 17 % | 22 % | 19 % | 15 % | 39 % | 32 % |
| La Niña, mean rain | −0.3 mm | +0.7 mm | +0.5 mm | +0.1 mm | +2.5 mm | +7.5 mm |
| IOD+ (hand-picked years), highs real | 10 % | 15 % | 12 % | 9 % | 13 % | 11 % |

- **ENSO is real** where the literature says it acts: South America,
  Oceania (eastern Australia), Africa, North America's winter, parts of Asia.
  Strong events are stronger still (strong El Niño: South American highs
  +0.45 °C, 45 % of cell-months real and noticeable), but have too few years
  for some months (strong La Niña: none in April–July), so they aren't built.
- **Europe barely responds**: its real shares are close to chance and its mean
  changes are a few hundredths of a degree. The app's help says so.
- **The IOD is at chance** over 45 years with the event years then available
  (calendar years from the Bureau of Meteorology's list), so it isn't built.
  Months picked from the Dipole Mode Index, like ENSO's, would be a fairer test,
  left open below.
- **Windows show the warming**: the last 10 years raise highs by 0.12–0.21 °C
  and hardly change rain; the last 5 raise them by 0.24–0.52 °C (Oceania
  −0.08 °C, three La Niña years), but change rain in 12–24 % of cell-months,
  about what 5 random years do: their rain is mostly those years' weather.
  The help tells riders to trust the 5-year temperatures more than its rain.

## Filtering the ENSO years: tested, not used

Would El Niño come out cleaner using only months where nothing else was
going on? Two checks (`python -m forkcast_data.variants_research checks`,
results in `cache/variants/checks-1981-2025.md`):

- **Volcanoes.** Leaving out 1982–83 (El Chichón) and 1991–93 (Pinatubo), from
  the events, the random sets and the trend: the El Niño average changed little
  (pattern correlation 0.91–0.94, 4–8 % of cell-months differing noticeably)
  and got no clearer, while losing 4 of 27 El Niño years. Not used.
- **IOD companions.** Leaving out the El Niño months that were also IOD+:
  the signal weakened (South American highs real 40 → 32 %, African lows
  35 → 26 %, Oceania 31 → 25 %). The IOD often comes with El Niño and is part
  of what an El Niño year brings, so a rider picking El Niño should get it.
  La Niña overlaps with IOD− in only 8 months, so it made no difference. Not
  used.

## What was built

- **Corrections, not averages.** An El Niño average over 1981–2025 would be
  about 0.5 °C colder than today, so El Niño would look cool almost
  everywhere. Instead each variant is the 2011–2025 grid plus a correction:
  the windows' difference from 2011–2025, or the phase's departure from the
  trend. Rain is corrected by a ratio, so it can't go negative.
- **Only where it beats chance.** A phase's correction is kept in full where it
  beats 90 % of the random sets, fades out towards their 75th percentile and
  is zero below. Without that, Europe's El Niño grid would show ±0.4 °C of
  noise that looks like signal.
- **Checks that stop the build** when a well-known ENSO effect comes out with
  the wrong sign, or temperatures move implausibly (`variants.check`).

## Open ends

- ERA5-Land's Tibetan Plateau winters jump by up to 14 °C from 2021 on
  (found by the build's checks), most likely its snow cover. Replacing those
  cell-months there with a trend from the earlier years, or calibrating the
  winter months with CRU per year, would fix both the 5-year variant and the
  2011–2025 grid.

- Continent-wide shares hide regional signals. A map of where each phase beats
  the noise would show riders where picking El Niño matters.
- IOD months from the Dipole Mode Index (NOAA PSL), tested like ENSO's, might
  show a real effect around the Indian Ocean (East Africa's short rains,
  southern Australia's spring). Its forecasts only reach about a season ahead.
- The strong ENSO variants, once more years exist, or with their missing
  months taken from the ordinary ones.
