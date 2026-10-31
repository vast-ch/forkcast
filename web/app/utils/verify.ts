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

const DIGITS: Record<string, number> = { '°C': 2, mm: 1, days: 2 };

/** A measured value as the nerd pages show it, e.g. "1.56 °C", "−8.1 mm". */
export function fmtMeasured(
  r: Measurement | undefined,
  signed = false,
): string {
  if (!r) return '–';
  const text = r.value.toFixed(DIGITS[r.unit] ?? 2);
  // A value that rounds to nothing shows no sign: "0.00", not "−0.00".
  const isZero = Number(text) === 0;
  const n = isZero ? text.replace('-', '') : text.replace('-', '−');
  const sign = signed && r.value > 0 && !isZero ? '+' : '';
  return `${sign}${n}${r.unit ? ' ' + r.unit : ''}`;
}
