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
  coldestNight: TripDay | undefined;
  /** Expected number of days with some rain, riding days only */
  rainyDays: number;
  rainMm: number;
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
      nightLow: isRest
        ? weather.low
        : climateOn(climate, date, sleep, settings.rainThreshold).low,
      daylight,
      needsLights: !isRest && ridingHours > daylight,
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
    coldestNight: coldest,
    rainyDays: valid.reduce((s, d) => s + d.weather.rainChance, 0),
    rainMm: valid.reduce((s, d) => s + d.weather.rainMm, 0),
  };
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
