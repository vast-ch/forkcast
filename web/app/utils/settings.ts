import { LAST_WEEK, weekOfDate } from './weeks';
import { RAIN_THRESHOLDS, type RainThreshold } from './climate';
import type { Milestones } from './itinerary';
import type {
  CityLimit,
  ClimateId,
  RainMetric,
  TempMetric,
} from 'forkcast/services/planner';

// Every setting lives in the URL query string, so a bookmark or reload restores
// it. Ember leaves a parameter out of the URL while it has its default value.

/** A date (today by default) as an ISO date, yyyy-mm-dd, in local time. */
export function isoDate(date = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export const DEFAULTS = {
  /** Continents whose climate is shown, comma-separated; Europe by default */
  continents: 'europe',
  /** Which climate: the average of the last 15, 10 or 5 years, or an El Niño or La Niña year */
  climate: 'last15' as ClimateId,
  /** Quarter-month shown on the map, 0–47 (see utils/weeks.ts); the current one by default */
  week: weekOfDate(new Date()),
  /** Temperature shown: day high or night low */
  tempMetric: 'high' as TempMetric,
  /** Show the temperature colours */
  showTemp: true,
  /** Show the rain */
  showRain: true,
  /** Map details: country outlines, relief shading, rivers and lakes, the other routes */
  borders: true,
  relief: true,
  water: true,
  routes: true,
  /** City names: the 10 biggest per country, every town over 500,000, or none */
  cities: 'top10' as CityLimit,
  /** Dates over the night stops: where each month or week of the trip begins, or none */
  dates: 'months' as Milestones,
  /** Rain on the map: rainy days as emoji, or mm as dots */
  rainMetric: 'days' as RainMetric,
  /** mm of rain from which a day counts as rainy */
  rainThreshold: 5 as RainThreshold,
  /** Selected route: a preset's id, or one of your routes' UUID; '' means the continents' default */
  routeId: '',
  /** First day of the trip; today by default */
  start: isoDate(),
  kmPerDay: 80,
  /** Average riding speed, km/h, for each day's time in the saddle */
  speed: 21,
  rideDays: 5,
  restDays: 1,
  isReversed: false,
  /** Highlighted trip day, 0 for none */
  highlightedDay: 0,
};

export type SettingKey = keyof typeof DEFAULTS;

/** Allowed values of the numeric trip settings, for the URL and the inputs alike. */
export const LIMITS = {
  kmPerDay: { min: 5, max: 400, step: 5, isInteger: false },
  speed: { min: 5, max: 50, step: 0.5, isInteger: false },
  rideDays: { min: 1, max: 60, step: 1, isInteger: true },
  restDays: { min: 0, max: 30, step: 1, isInteger: true },
} as const;
export type LimitedKey = keyof typeof LIMITS;

export function inLimits(key: LimitedKey, v: number): boolean {
  const l = LIMITS[key];
  return (
    Number.isFinite(v) &&
    v >= l.min &&
    v <= l.max &&
    (!l.isInteger || Number.isInteger(v))
  );
}

/** A date as the date input and the URL hold it: yyyy-mm-dd. */
export const isIsoDate = (v: string): boolean => /^\d{4}-\d{2}-\d{2}$/.test(v);
export const SETTING_KEYS = Object.keys(DEFAULTS) as SettingKey[];

// What the URL holds is checked when read: anything a parser rejects
// (undefined) reads as the setting's default.

type Parse<T> = (v: unknown) => T | undefined;
const oneOf =
  <T>(values: readonly T[]): Parse<T> =>
  (v) =>
    values.find((x) => x === v);
const isBoolean: Parse<boolean> = (v) =>
  typeof v === 'boolean' ? v : undefined;
const isText: Parse<string> = (v) => (typeof v === 'string' ? v : undefined);
const isWholeIn =
  (min: number, max: number): Parse<number> =>
  (v) =>
    Number.isInteger(v) && (v as number) >= min && (v as number) <= max
      ? (v as number)
      : undefined;
const inRange =
  (key: LimitedKey): Parse<number> =>
  (v) =>
    typeof v === 'number' && inLimits(key, v) ? v : undefined;

export const PARSE: { [K in SettingKey]: Parse<(typeof DEFAULTS)[K]> } = {
  continents: isText,
  climate: oneOf(['last15', 'last10', 'last5', 'elnino', 'lanina'] as const),
  week: isWholeIn(0, LAST_WEEK),
  tempMetric: oneOf(['high', 'low'] as const),
  showTemp: isBoolean,
  showRain: isBoolean,
  borders: isBoolean,
  relief: isBoolean,
  water: isBoolean,
  routes: isBoolean,
  cities: oneOf(['top10', 'big', 'off'] as const),
  dates: oneOf(['months', 'weeks', 'off'] as const),
  rainMetric: oneOf(['days', 'mm'] as const),
  rainThreshold: oneOf(RAIN_THRESHOLDS),
  routeId: isText,
  start: (v) => (typeof v === 'string' && isIsoDate(v) ? v : undefined),
  kmPerDay: inRange('kmPerDay'),
  speed: inRange('speed'),
  rideDays: inRange('rideDays'),
  restDays: inRange('restDays'),
  isReversed: isBoolean,
  highlightedDay: isWholeIn(0, Infinity),
};
