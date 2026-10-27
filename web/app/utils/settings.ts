import { weekOfDate } from './weeks';

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
  /** Quarter-month shown on the map, 1–48 (see utils/weeks.ts); the current one by default */
  week: weekOfDate(new Date()) + 1,
  /** Temperature shown: day high or night low */
  temp: 'high' as 'high' | 'low',
  /** Show the temperature colours */
  heat: true,
  /** Show the rain dots */
  rain: true,
  /** Map details: country outlines, city and range names, relief shading, rivers and lakes */
  borders: true,
  cities: true,
  relief: true,
  water: true,
  /** The preset routes other than the selected one, dashed */
  routes: true,
  /** Dates over the night stops: where each month or week of the trip begins, or none */
  dates: 'months' as 'months' | 'weeks' | 'off',
  /** Rain on the map: rainy days as emoji, or mm as dots */
  dots: 'days' as 'mm' | 'days',
  /** mm of rain from which a day counts as rainy */
  rainy: 5,
  /** Selected route: a preset's id, or one of your routes' UUID; '' means the continent's default */
  route: '',
  /** First day of the trip; today by default */
  start: isoDate(),
  km: 80,
  /** Average riding speed, km/h, for each day's time in the saddle */
  speed: 21,
  ride: 5,
  rest: 1,
  reverse: false,
  /** Highlighted trip day, 0 for none */
  day: 0,
  /** Old links only: a route carried in the link itself (see encodeTrack) and
   * its name; it's saved to your routes on opening (IndexRoute.redirect) */
  track: '',
  name: '',
};

export type SettingKey = keyof typeof DEFAULTS;

/** Allowed values of the numeric trip settings, for the URL and the inputs alike. */
export const LIMITS = {
  km: { min: 5, max: 400, step: 5, isInteger: false },
  speed: { min: 5, max: 50, step: 0.5, isInteger: false },
  ride: { min: 1, max: 60, step: 1, isInteger: true },
  rest: { min: 0, max: 30, step: 1, isInteger: true },
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
