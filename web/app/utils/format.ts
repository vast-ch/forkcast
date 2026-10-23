import { htmlSafe } from '@ember/template';

export const fmtTemp = (t: number | undefined | null): string =>
  t === undefined || t === null || Number.isNaN(t) ? '–' : `${Math.round(t)}°`;

export const fmtKm = (km: number): string =>
  km >= 100 ? `${Math.round(km).toLocaleString()} km` : `${km.toFixed(1)} km`;

export const fmtPct = (p: number): string =>
  Number.isNaN(p) ? '–' : `${Math.round(p * 100)}%`;

export const fmtMm = (mm: number): string =>
  Number.isNaN(mm)
    ? '–'
    : mm < 10
      ? `${mm.toFixed(1)} mm`
      : `${Math.round(mm)} mm`;

export const fmtDate = (d: Date): string =>
  d.toLocaleDateString(undefined, {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  });

export const fmtShortDate = (d: Date): string =>
  d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });

/** "Day 3 · Sat 25 Oct" */
export const fmtDayTitle = (d: { n: number; date: Date }): string =>
  `Day ${d.n} · ${fmtDate(d.date)}`;

/** Inline style from a value we computed ourselves (colours, sizes), marked safe for binding. */
export const css = (...parts: (string | number)[]) => htmlSafe(parts.join(''));
