import { htmlSafe } from '@ember/template';
import { isMissing } from './helpers';

export const fmtTemp = (t: number | undefined | null): string =>
  isMissing(t) ? '–' : `${Math.round(t)}°C`;

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

/** Hours of daylight: "10h 41min"; the polar extremes are named. */
export const fmtDaylight = (h: number): string => {
  if (h >= 24) return '24h (midnight sun)';
  if (h <= 0) return 'None (polar night)';
  const mins = Math.round(h * 60);
  return `${Math.floor(mins / 60)}h ${String(mins % 60).padStart(2, '0')}min`;
};

/** The month's full name, e.g. "November". */
export const fmtMonth = (d: Date): string =>
  d.toLocaleDateString(undefined, { month: 'long' });

/** "Day 3 · Sat 25 Oct" */
export const fmtDayTitle = (d: { n: number; date: Date }): string =>
  `Day ${d.n} · ${fmtDate(d.date)}`;

/** Inline style from a value we computed ourselves (colours, sizes), marked safe for binding. */
export const css = (...parts: (string | number)[]) => htmlSafe(parts.join(''));
