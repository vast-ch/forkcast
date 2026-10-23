import { weekOfDate } from './weeks';

// Every setting lives in the URL query string, so a bookmark or reload restores
// it. Ember leaves a parameter out of the URL while it has its default value.

/** The coming 1 January (today, if it is 1 January). */
export function nextJanuary(today = new Date()): string {
  const isNewYearsDay = today.getMonth() === 0 && today.getDate() === 1;
  return `${isNewYearsDay ? today.getFullYear() : today.getFullYear() + 1}-01-01`;
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
  start: nextJanuary(),
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
export const SETTING_KEYS = Object.keys(DEFAULTS) as SettingKey[];

/** Route id used for your own route (from `track`). */
export const OWN_ROUTE_ID = 'mine';
