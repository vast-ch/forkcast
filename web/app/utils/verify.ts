// The data's measured precision (data/out/verify/latest.json, written by the
// data pipeline's `verify` step), for the help's Nerd mode. Accuracy numbers
// on the nerd pages come from here, never typed into the page.

import { fetchJson } from './assets';

export interface Measurement {
  metric: string;
  climate: string;
  field: string;
  area: string;
  stat: string;
  value: number;
  unit: string;
}

export interface Measurements {
  /** When and with which code they were measured, and the code of the grids measured. */
  run: { date: string; code: string; grids: string };
  /** First and last year the climates were backtested on. */
  backtest: [number, number];
  results: Measurement[];
}

let loading: Promise<Measurements> | undefined;

/** The latest measurements, fetched once (only nerd pages ask for them). */
export function loadMeasurements(): Promise<Measurements> {
  return (loading ??= fetchJson<Measurements>('verify/latest.json'));
}

/** The one measurement matching every given field, if there is one. */
export function measured(
  m: Measurements,
  q: Partial<Omit<Measurement, 'value' | 'unit'>>,
): Measurement | undefined {
  return m.results.find((r) =>
    Object.entries(q).every(([k, v]) => r[k as keyof Measurement] === v),
  );
}

/** What a measurement the data doesn't have shows as. */
export const MISSING = 'not measured';

// Shares are fractions of 1, shown as percent with one decimal.
const DIGITS: Record<string, number> = {
  '°C': 2,
  '°C per km': 1,
  mm: 1,
  days: 2,
  kB: 0,
  MB: 1,
  places: 0,
  trips: 0,
  tiles: 0,
  years: 0,
  '%': 1,
};

/** A measured value as the nerd pages show it, e.g. "1.56 °C", "−8.1 mm". */
export function fmtMeasured(
  r: Measurement | undefined,
  signed = false,
): string {
  if (!r) return MISSING;
  if (r.unit === 'share') {
    const pct = { ...r, value: r.value * 100, unit: '%' };
    return fmtMeasured(pct, signed).replace(' %', '%');
  }
  const text = r.value.toFixed(DIGITS[r.unit] ?? 2);
  // A value that rounds to nothing shows no sign: "0.00", not "−0.00".
  const isZero = Number(text) === 0;
  const n = isZero ? text.replace('-', '') : text.replace('-', '−');
  const sign = signed && r.value > 0 && !isZero ? '+' : '';
  return `${sign}${n}${r.unit ? ' ' + r.unit : ''}`;
}

type Query = [metric: string, field: string, area: string, stat: string];

/** One measured value, formatted; for templates: `{{value m "range" "tmx" "World" "below"}}`. */
export function value(m: Measurements, ...[metric, field, area, stat]: Query) {
  return fmtMeasured(measured(m, { metric, field, area, stat }));
}

/** The same, signed (+0.48 °C). */
export function signed(m: Measurements, ...[metric, field, area, stat]: Query) {
  return fmtMeasured(measured(m, { metric, field, area, stat }), true);
}

/** A measured value with its 95% interval: "11.7% (11.1% to 12.3%)". */
export function withInterval(
  m: Measurements,
  ...[metric, field, area, stat]: Query
) {
  const get = (s: string) => measured(m, { metric, field, area, stat: s });
  const lo = get(`${stat} lo95`);
  const hi = get(`${stat} hi95`);
  const v = fmtMeasured(get(stat));
  return lo && hi ? `${v} (${fmtMeasured(lo)} to ${fmtMeasured(hi)})` : v;
}
