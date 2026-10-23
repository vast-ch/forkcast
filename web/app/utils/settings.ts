import { weekOfDate } from './weeks';

// Every setting lives in the URL query string, so a bookmark or reload restores
// it. Ember leaves a parameter out of the URL while it has its default value.

/** Today as an ISO date (yyyy-mm-dd), in local time. */
export function isoToday(today = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}`;
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
  /** Rain dots: monthly mm or rainy days */
  dots: 'mm' as 'mm' | 'days',
  /** mm of rain from which a day counts as rainy */
  rainy: 5,
  /** Selected route id; '' means the continent's default */
  route: '',
  /** First day of the trip; today by default */
  start: isoToday(),
  km: 80,
  ride: 5,
  rest: 1,
  reverse: false,
  /** Highlighted trip day, 0 for none */
  day: 0,
  /** Your own route, encoded (see encodeTrack) */
  track: '',
  /** Name of your own route */
  name: '',
};

export type SettingKey = keyof typeof DEFAULTS;

/** Allowed values of the numeric trip settings, for the URL and the inputs alike. */
export const LIMITS = {
  km: { min: 5, max: 400, step: 5, isInteger: false },
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

/** Route id used for your own route (from `track`). */
export const OWN_ROUTE_ID = 'mine';
