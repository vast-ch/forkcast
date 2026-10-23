// Splits a route into riding days and rest days, and attaches the expected
// weather for each day from the climate normals.

import type ClimateGrid from './climate';
import type { DayClimate } from './climate';
import {
  climbBetween,
  pointAt,
  townNear,
  type Route,
  type RoutePoint,
} from './route';

export interface TripSettings {
  /** First day of the trip, ISO date (yyyy-mm-dd) */
  start: string;
  kmPerDay: number;
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
  sleepTown?: string;
  /** Weather at the middle of the day's ride (or at the rest stop) */
  weather: DayClimate;
  /** Low at the overnight stop */
  nightLow: number;
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
  climate: ClimateGrid,
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
    if (isRest) {
      const here = pointAt(route.points, km);
      const weather = climate.on(
        date,
        here.lat,
        here.lon,
        settings.rainThreshold,
      );
      days.push({
        n,
        date,
        isRest: true,
        fromKm: km,
        toKm: km,
        distance: 0,
        climb: 0,
        sleep: here,
        sleepTown: townNear(route, km),
        weather,
        nightLow: weather.low,
      });
      continue;
    }
    const to = Math.min(total, km + perDay);
    const mid = pointAt(route.points, (km + to) / 2);
    const sleep = pointAt(route.points, to);
    days.push({
      n,
      date,
      isRest: false,
      fromKm: km,
      toKm: to,
      distance: to - km,
      climb: climbBetween(route.points, km, to),
      sleep,
      sleepTown: townNear(route, to),
      weather: climate.on(date, mid.lat, mid.lon, settings.rainThreshold),
      nightLow: climate.on(date, sleep.lat, sleep.lon, settings.rainThreshold)
        .low,
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

/** The trip day during which a rider passes `km`. */
export function dayAtKm(trip: Trip, km: number): TripDay | undefined {
  return trip.days.find(
    (d) => !d.isRest && km >= d.fromKm && km <= d.toKm + 1e-6,
  );
}
