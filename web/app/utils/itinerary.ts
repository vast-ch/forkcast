// Splits a route into riding days and rest days, and attaches the expected
// weather for each day from the climate normals.

import { climateOn, type ClimateSource, type DayClimate } from './climate';
import { climbBetween, pointAt, type Route, type RoutePoint } from './route';
import { fmtShortMonth } from './format';
import { daylightHours } from './sun';

export interface TripSettings {
  /** First day of the trip, ISO date (yyyy-mm-dd) */
  start: string;
  kmPerDay: number;
  /** Average riding speed, km/h */
  speed: number;
  /** Riding days in a row… */
  rideDays: number;
  /** …followed by this many rest days, then the pattern repeats. 0 means no rest days. */
  restDays: number;
  /** mm of rain from which a day counts as rainy */
  rainThreshold: number;
}

export interface TripDay {
  /** 1-based day number */
  n: number;
  date: Date;
  isRest: boolean;
  fromKm: number;
  toKm: number;
  distance: number;
  climb: number | null;
  /** Where the night is spent (end of the day's ride) */
  sleep: RoutePoint;
  /** Weather at the middle of the day's ride (or at the rest stop) */
  weather: DayClimate;
  /** Low at the overnight stop */
  nightLow: number;
  /** How far single lows there stray from it (°C, a standard deviation) */
  nightLowSpread: number;
  /** The average headwind over the day's stretch, m/s; negative is a tailwind (NaN on rest days or without wind data) */
  headwind: number;
  /** Hours in the saddle at the average speed (0 on rest days) */
  ridingHours: number;
  /** More riding time than daylight: part of the day is ridden in the dark */
  needsLights: boolean;
  /** Hours from sunrise where the day starts to sunset where it ends (24 under the midnight sun, 0 in the polar night) */
  daylight: number;
}

export interface Trip {
  days: TripDay[];
  ridingDays: number;
  restDays: number;
  end: Date;
  km: number;
  avgHigh: number;
  lowestLow: TripDay | undefined;
  /** The trip's lowest single low, in an average year: as likely to come out colder as warmer (see likelyExtreme) */
  likelyLowest: number;
  /** The same for its highest high on a riding day */
  likelyHighest: number;
  /** Expected number of days with some rain, riding days only */
  rainyDays: number;
  /** Fewest and most rainy riding days in 8 trips out of 10 (see rainyDaysRange) */
  rainyDaysRange: [number, number];
  rainMm: number;
  /** The average headwind over the riding days, by distance, m/s (negative: a tailwind) */
  headwind: number;
}

/**
 * The average headwind riding from `a` to `b` over `distance` km, with the
 * same wind all along: the wind against the net direction, scaled by how
 * much of the distance went that way. However the road winds, its pieces add
 * up to the straight line from a to b, and a constant wind's push along them
 * adds up the same way.
 */
export function headwindBetween(
  a: { lat: number; lon: number },
  b: { lat: number; lon: number },
  distance: number,
  u: number,
  v: number,
): number {
  if (!(distance > 0) || Number.isNaN(u) || Number.isNaN(v)) return Number.NaN;
  const east =
    (b.lon - a.lon) *
    111.32 *
    Math.cos((((a.lat + b.lat) / 2) * Math.PI) / 180);
  const north = (b.lat - a.lat) * 110.57;
  return -(u * east + v * north) / distance;
}

export function parseDate(iso: string): Date {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y!, (m ?? 1) - 1, d ?? 1, 12);
}

export function addDays(date: Date, n: number): Date {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

export function planTrip(
  route: Route,
  climate: ClimateSource,
  settings: TripSettings,
): Trip {
  const total = route.points[route.points.length - 1]?.km ?? 0;
  const perDay = Math.max(5, settings.kmPerDay);
  const start = parseDate(settings.start);
  const days: TripDay[] = [];
  const ride = Math.max(1, Math.floor(settings.rideDays));
  const rest = Math.max(0, Math.floor(settings.restDays));
  const cycle = ride + rest;
  let km = 0;
  let n = 0;
  // Guard against silly inputs producing thousands of days.
  while (km < total - 0.05 && n < 1000) {
    const date = addDays(start, n);
    // Position in the ride/rest pattern; the loop only continues while there is
    // still distance left, so a trip never ends on a rest day.
    const isRest = rest > 0 && n % cycle >= ride;
    n++;
    // A rest day is a day that ends where it started.
    const to = isRest ? km : Math.min(total, km + perDay);
    const here = pointAt(route.points, km);
    const mid = pointAt(route.points, (km + to) / 2);
    const sleep = pointAt(route.points, to);
    const weather = climateOn(climate, date, mid, settings.rainThreshold);
    const night = isRest
      ? weather
      : climateOn(climate, date, sleep, settings.rainThreshold);
    const daylight = daylightHours(date, here, sleep);
    const ridingHours = (to - km) / settings.speed;
    days.push({
      n,
      date,
      isRest,
      fromKm: km,
      toKm: to,
      distance: to - km,
      ridingHours,
      climb: isRest ? 0 : climbBetween(route.points, km, to),
      sleep,
      weather,
      nightLow: night.low,
      nightLowSpread: night.lowSpread,
      daylight,
      needsLights: !isRest && ridingHours > daylight,
      headwind: isRest
        ? Number.NaN
        : headwindBetween(here, sleep, to - km, weather.windU, weather.windV),
    });
    km = to;
  }
  const riding = days.filter((d) => !d.isRest);
  const valid = riding.filter((d) => !Number.isNaN(d.weather.high));
  let coldest: TripDay | undefined;
  for (const d of days) {
    if (
      !Number.isNaN(d.nightLow) &&
      (!coldest || d.nightLow < coldest.nightLow)
    ) {
      coldest = d;
    }
  }
  return {
    days,
    ridingDays: riding.length,
    restDays: days.length - riding.length,
    end: days[days.length - 1]?.date ?? start,
    km: total,
    avgHigh:
      valid.reduce((s, d) => s + d.weather.high, 0) / (valid.length || 1),
    lowestLow: coldest,
    likelyLowest: likelyExtreme(
      days.map((d) => [d.nightLow, d.nightLowSpread]),
      'lowest',
    ),
    likelyHighest: likelyExtreme(
      valid.map((d) => [d.weather.high, d.weather.highSpread]),
      'highest',
    ),
    rainyDays: valid.reduce((s, d) => s + d.weather.rainChance, 0),
    rainyDaysRange: rainyDaysRange(
      valid.map((d) => d.weather.rainChance),
      settings.rainThreshold,
    ),
    rainMm: valid.reduce((s, d) => s + d.weather.rainMm, 0),
    headwind: averageHeadwind(riding),
  };
}

/**
 * How much more the number of rainy days in a stretch of days varies from year
 * to year than it would if each day's rain were independent of the next: rain
 * comes in spells. Measured on the daily ERA5-Land rain, 2011–2025, as the
 * median over land of the variance across years against independent days'
 * (windows of one week to two months; heavier rain clusters less).
 */
const SPELL_FACTOR: Record<number, number> = { 1: 2, 5: 1.6, 10: 1.5 };

/** The riding days' headwind, weighted by their distance (NaN without wind data). */
function averageHeadwind(days: TripDay[]): number {
  const known = days.filter((d) => !Number.isNaN(d.headwind));
  const km = known.reduce((s, d) => s + d.distance, 0);
  return km > 0
    ? known.reduce((s, d) => s + d.headwind * d.distance, 0) / km
    : Number.NaN;
}

/** Share of trips below the range, and above it. */
const RANGE_TAIL = 0.1;

/**
 * Low lows and high highs come in spells, so a trip's lows are fewer
 * independent tries at a low one than there are lows: about one in 2, and
 * one in 2.5 for hot days. Measured on NOAA CPC's daily highs and lows,
 * 2011–2025, at 1,200 random places, trips of 7 to 60 days: with these, the
 * real lowest low came out below likelyExtreme's in 47–51% of trips (the
 * highest high above it in 40–58%), against 21–32% counting every day.
 */
const EXTREME_SPELL = { lowest: 2, highest: 2.5 } as const;

/** The normal distribution's cumulative probability (Abramowitz–Stegun 7.1.26, within 1.5e-7). */
function normalCdf(z: number): number {
  const a = Math.abs(z) / Math.SQRT2;
  const t = 1 / (1 + 0.3275911 * a);
  const erf =
    1 -
    ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) *
      t +
      0.254829592) *
      t *
      Math.exp(-a * a);
  return 0.5 * (1 + Math.sign(z) * erf);
}

/**
 * The lowest (or highest) single value over some days, each [mean, spread]
 * with normally distributed days, that the trip is as likely to beat as not:
 * x where the chance that every day stays on the mild side of it, counted
 * over 1 in EXTREME_SPELL days (but at least one), is one half. NaN without
 * spreads.
 */
export function likelyExtreme(
  days: [number, number][],
  side: 'lowest' | 'highest',
): number {
  const known = days.filter(([m, s]) => !Number.isNaN(m) && s > 0);
  if (known.length === 0) return Number.NaN;
  const sign = side === 'lowest' ? -1 : 1;
  // In "how far beyond" terms (−x for the lowest), so both sides search alike.
  // At least one try: a trip shorter than a spell gets its days' typical value.
  const target = Math.min(EXTREME_SPELL[side], known.length) * Math.log(0.5);
  const logMild = (x: number) =>
    known.reduce(
      (sum, [m, s]) =>
        sum + Math.log(Math.max(1e-300, normalCdf((x - sign * m) / s))),
      0,
    );
  let lo = Math.min(...known.map(([m, s]) => sign * m - 6 * s));
  let hi = Math.max(...known.map(([m, s]) => sign * m + 6 * s));
  for (let i = 0; i < 50; i++) {
    const mid = (lo + hi) / 2;
    if (logMild(mid) < target) lo = mid;
    else hi = mid;
  }
  return (sign * (lo + hi)) / 2;
}

/**
 * The fewest and most rainy days in 8 trips out of 10, given each day's chance.
 * The count is taken as beta-binomial: the days' average chance, with spread
 * widened by SPELL_FACTOR from what independent days would give.
 */
export function rainyDaysRange(
  chances: number[],
  threshold: number,
): [number, number] {
  const n = chances.length;
  const p = chances.reduce((s, c) => s + c, 0) / (n || 1);
  if (n === 0 || p <= 0) return [0, 0];
  if (p >= 1) return [n, n];
  const independent = chances.reduce((s, c) => s + c * (1 - c), 0);
  const target = (SPELL_FACTOR[threshold] ?? 2) * independent;
  // Beta-binomial variance is n p (1 − p) (1 + (n − 1) ρ); solve for ρ.
  const rho =
    n > 1 ? Math.max(0, (target / (n * p * (1 - p)) - 1) / (n - 1)) : 0;
  const pmf = new Array<number>(n + 1);
  if (rho < 1e-9) {
    pmf[0] = (1 - p) ** n;
    for (let k = 0; k < n; k++)
      pmf[k + 1] = (pmf[k]! * (n - k) * p) / ((k + 1) * (1 - p));
  } else {
    const a = p * (1 / rho - 1);
    const b = (1 - p) * (1 / rho - 1);
    pmf[0] = 1;
    for (let i = 0; i < n; i++) pmf[0] *= (b + i) / (a + b + i);
    for (let k = 0; k < n; k++)
      pmf[k + 1] = (pmf[k]! * (n - k) * (a + k)) / ((k + 1) * (b + n - k - 1));
  }
  let low = 0;
  let high = n;
  let sum = 0;
  for (let k = 0; k <= n; k++) {
    const before = sum;
    sum += pmf[k]!;
    if (before < RANGE_TAIL && sum >= RANGE_TAIL) low = k;
    if (before < 1 - RANGE_TAIL && sum >= 1 - RANGE_TAIL) high = k;
  }
  return [low, high];
}

/** Where the map marks the trip's progress: at each new month or week, or nowhere. */
export type Milestones = 'months' | 'weeks' | 'off';

/**
 * The days that get a tag on the map, at their night stop: the 1st of each
 * month ("Nov") or the first day of each week of the trip ("Week 2"). A rest
 * day is tagged like any other, where the rider rests.
 */
export function milestones(
  trip: Trip,
  by: Milestones,
): { day: TripDay; label: string }[] {
  return trip.days.flatMap((day) => {
    if (by === 'months' && day.date.getDate() === 1)
      return [{ day, label: fmtShortMonth(day.date) }];
    if (by === 'weeks' && (day.n - 1) % 7 === 0)
      return [{ day, label: `Week ${(day.n - 1) / 7 + 1}` }];
    return [];
  });
}

/** The trip day during which a rider passes `km`. */
export function dayAtKm(trip: Trip, km: number): TripDay | undefined {
  return trip.days.find(
    (d) => !d.isRest && km >= d.fromKm && km <= d.toKm + 1e-6,
  );
}
