import { htmlSafe } from '@ember/template';
import { STEADY, usualRange, windFrom } from './climate';
import type { WindPush } from './itinerary';
import { isMissing } from './helpers';

export const fmtTemp = (t: number | undefined | null): string =>
  isMissing(t) ? '–' : `${Math.round(t)}°C`;

/** A temperature's usual range (see usualRange): "(19 to 29°C)", or "" without a spread. */
export const fmtUsual = (mean: number, spread: number): string => {
  if (isMissing(mean) || isMissing(spread)) return '';
  const [lo, hi] = usualRange(mean, spread);
  return `(${Math.round(lo)} to ${Math.round(hi)}°C)`;
};

const PUSH_WORDS: Record<WindPush, string> = {
  against: 'against you',
  behind: 'behind you',
  side: 'from the side',
  varied: 'from all sides',
};

/** A day's wind: "15 km/h, against you". */
export const fmtRideWind = (mps: number, push?: WindPush): string => {
  if (isMissing(mps)) return '–';
  const kmh = `${Math.round(mps * 3.6)} km/h`;
  return push ? `${kmh}, ${PUSH_WORDS[push]}` : kmh;
};

/** The trip's wind: "14 km/h, against you", or "neither way". */
export const fmtTripWind = (mps: number, push?: WindPush): string => {
  if (isMissing(mps)) return '–';
  const kmh = `${Math.round(mps * 3.6)} km/h`;
  if (push === 'against' || push === 'behind')
    return `${kmh}, ${PUSH_WORDS[push]}`;
  return push ? `${kmh}, neither way` : kmh;
};

/** The wind at a spot: "15 km/h SW", or "15 km/h" when it blows from any side. */
export const fmtWind = (
  mps: number,
  u: number,
  v: number,
  steadiness: number,
): string => {
  if (isMissing(mps)) return '–';
  const kmh = `${Math.round(mps * 3.6)} km/h`;
  // The side it blows from, as on a forecast; none when that changes daily.
  return steadiness < STEADY ? kmh : `${kmh} ${windFrom(u, v)}`;
};

export const fmtKm = (km: number): string =>
  km >= 100 ? `${Math.round(km).toLocaleString()}km` : `${km.toFixed(1)}km`;

export const fmtPct = (p: number): string =>
  Number.isNaN(p) ? '–' : `${Math.round(p * 100)}%`;

export const fmtMm = (mm: number): string =>
  Number.isNaN(mm)
    ? '–'
    : mm < 10
      ? `${mm.toFixed(1)}mm`
      : `${Math.round(mm)}mm`;

export const fmtDate = (d: Date): string =>
  d.toLocaleDateString(undefined, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });

export const fmtShortDate = (d: Date): string =>
  d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });

/** A duration in hours: "3h 49min". */
export const fmtHours = (h: number): string => {
  const mins = Math.round(h * 60);
  return `${Math.floor(mins / 60)}h ${String(mins % 60).padStart(2, '0')}min`;
};

/** Hours of daylight: "10h 41min"; the polar extremes are named. */
export const fmtDaylight = (h: number): string => {
  if (h >= 24) return '24h (midnight sun)';
  if (h <= 0) return 'None (polar night)';
  return fmtHours(h);
};

/** The month's short name, e.g. "Nov". */
export const fmtShortMonth = (d: Date): string =>
  d.toLocaleDateString(undefined, { month: 'short' });

/** The month's full name, e.g. "November". */
export const fmtMonth = (d: Date): string =>
  d.toLocaleDateString(undefined, { month: 'long' });

/** "Day 3 · Sat 25 Oct" */
export const fmtDayTitle = (d: { n: number; date: Date }): string =>
  `Day ${d.n} · ${fmtDate(d.date)}`;

/** Inline style from a value we computed ourselves (colours, sizes), marked safe for binding. */
export const css = (...parts: (string | number)[]) => htmlSafe(parts.join(''));

/** Expected rainy days with the range 8 trips out of 10 fall in, e.g. "9 (6–12)". */
export const fmtRainyDays = (
  expected: number,
  [low, high]: [number, number],
): string =>
  low === high
    ? String(Math.round(expected))
    : `${Math.round(expected)} (${low}–${high})`;
