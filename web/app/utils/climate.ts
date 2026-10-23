// Climate normals on a regular lat/lon grid, one file per continent (built by
// data/forkcast_data/era5land.py, or climate.py for the older CRU grid).

/** How a stored byte maps to a value (ERA5-Land grids). */
export type Encoding =
  | { kind: 'linear'; scale: number; offset: number }
  | { kind: 'sqrt'; scale: number };

/** Header of a continent's climate grid (data/out/<continent>/climate.json). */
export interface ClimateHeader {
  source: string;
  years: [number, number];
  lon0: number; // centre of the first column
  lat0: number; // centre of the first (northernmost) row
  step: number;
  cols: number;
  rows: number;
  /** "u8": one byte per value with `encoding`; otherwise int16 with `scale` (CRU) */
  dtype?: 'u8';
  vars: ClimateVar[];
  /** Layers without months, stored after the monthly ones (u8 grids). */
  static?: ClimateVar[];
  scale?: Partial<Record<ClimateVar, number>>;
  encoding?: Partial<Record<ClimateVar, Encoding>>;
  nodata: number;
}

/**
 * tmx/tmn: mean daily max/min °C; pre: mm per month;
 * wet: days ≥ 0.1 mm (CRU); r1/r5/r10: days ≥ 1/5/10 mm (ERA5-Land).
 */
export type ClimateVar =
  'tmx' | 'tmn' | 'pre' | 'wet' | 'r1' | 'r5' | 'r10' | 'elev';

/**
 * How much the air cools with height, °C per metre, by month (Jan … Dec).
 * The yearly average is the familiar 6.5 °C per 1,000 m, but it is smaller in
 * winter, when cold air settles in valleys, and larger in summer. Values are
 * the seasonal lapse rates measured across the Alps (Rolland 2003, J. Climate
 * 16:1032-1046), rounded.
 */
export const LAPSE_RATES = [
  0.0045, 0.005, 0.0058, 0.0064, 0.0067, 0.0068, 0.0068, 0.0066, 0.006, 0.0054,
  0.0048, 0.0044,
];

/** Expected weather for one place on one day of the year. */
export interface DayClimate {
  /** Mean daily high, °C */
  high: number;
  /** Mean daily low, °C */
  low: number;
  /** Mean precipitation per day, mm */
  rainMm: number;
  /** Chance of a rainy day (at least the chosen threshold of rain), 0..1 */
  rainChance: number;
  /** Monthly totals of the month the day falls in, for the legend-style readout. */
  monthRainMm: number;
  /** Rainy days in the month, at the chosen threshold */
  monthWetDays: number;
  /** °C added to high and low for the point's height versus its grid cell (0 if unknown) */
  altitudeShift: number;
}

/** Rain thresholds offered for counting a day as rainy, mm. */
export const RAIN_THRESHOLDS = [1, 5, 10] as const;
export type RainThreshold = (typeof RAIN_THRESHOLDS)[number];

/**
 * Days per month with at least `threshold` mm of rain.
 *
 * CRU only counts wet days at ≥ 0.1 mm. Rain amounts on wet days are close to
 * exponentially distributed, with the mean being the month's total divided by
 * its wet days; the share of wet days reaching the threshold is then
 * exp(-(threshold - 0.1) / mean). An estimate, but a standard one.
 */
export function rainyDays(
  monthMm: number,
  wetDays: number,
  threshold: number,
): number {
  if (!(wetDays > 0) || !(monthMm > 0)) return 0;
  const mean = monthMm / wetDays;
  return wetDays * Math.exp(-Math.max(0, threshold - 0.1) / mean);
}

export const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
] as const;

function clamp01(x: number): number {
  return Number.isNaN(x) ? x : Math.min(1, Math.max(0, x));
}

const DAYS_IN_MONTH = [31, 28.25, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/** The stored rainy-day count for a threshold (1, 5 or 10 mm). */
function countVar(threshold: number): ClimateVar {
  return threshold <= 1 ? 'r1' : threshold >= 10 ? 'r10' : 'r5';
}

function decoder(header: ClimateHeader, v: ClimateVar): (x: number) => number {
  const e = header.encoding?.[v];
  if (e?.kind === 'sqrt') return (x) => (x / e.scale) ** 2;
  if (e?.kind === 'linear') return (x) => x / e.scale + e.offset;
  const scale = header.scale?.[v] ?? 1;
  return (x) => x / scale;
}

/** Number of yearly waves in the seasonal curve: 12-, 6- and 4-month cycles. */
const HARMONICS = 3;
const TERMS = 1 + 2 * HARMONICS;
/**
 * A month's average flattens each wave a little compared with its value at
 * mid-month (by sin(πk/12) / (πk/12) for the k-th wave). The fitted waves are
 * scaled back up by that factor, so peaks are not too mild.
 */
const FLATTENING = Array.from({ length: HARMONICS }, (_, i) => {
  const x = (Math.PI * (i + 1)) / 12;
  return Math.sin(x) / x;
});

/** Position in the year, 0 … 1 (0 = 1 January 00:00). */
export function phaseOfDate(date: Date): number {
  const start = new Date(date.getFullYear(), 0, 1);
  const end = new Date(date.getFullYear() + 1, 0, 1);
  return (date.getTime() - start.getTime()) / (end.getTime() - start.getTime());
}

/** Middle of a calendar month (0–11) as a position in the year. */
export function phaseOfMonth(month: number): number {
  return (month + 0.5) / 12;
}

/**
 * Smooth seasonal curve through 12 monthly averages: the yearly mean plus
 * HARMONICS waves. Writes TERMS coefficients for one cell into `out` at `at`.
 */
function fitSeason(values: number[], out: Float32Array, at: number): void {
  let mean = 0;
  for (const v of values) mean += v;
  out[at] = mean / 12;
  for (let k = 1; k <= HARMONICS; k++) {
    let a = 0;
    let b = 0;
    for (let m = 0; m < 12; m++) {
      const t = 2 * Math.PI * k * phaseOfMonth(m);
      a += values[m]! * Math.cos(t);
      b += values[m]! * Math.sin(t);
    }
    const f = FLATTENING[k - 1]!;
    out[at + 2 * k - 1] = a / 6 / f;
    out[at + 2 * k] = b / 6 / f;
  }
}

function evalSeason(c: Float32Array, at: number, phase: number): number {
  let v = c[at]!;
  for (let k = 1; k <= HARMONICS; k++) {
    const t = 2 * Math.PI * k * phase;
    v += c[at + 2 * k - 1]! * Math.cos(t) + c[at + 2 * k]! * Math.sin(t);
  }
  return v;
}

/** Lapse rate at a position in the year, blended between mid-month values. */
function lapseRateAt(phase: number): number {
  const x = phase * 12 - 0.5;
  const m0 = Math.floor(x);
  const t = x - m0;
  const a = LAPSE_RATES[((m0 % 12) + 12) % 12]!;
  const b = LAPSE_RATES[(((m0 + 1) % 12) + 12) % 12]!;
  return a + (b - a) * t;
}

/** Seasonal quantities smoothed as daily rates: per-month totals are divided by the month's days first. */
type SeasonVar = 'tmx' | 'tmn' | 'pre' | 'r1' | 'r5' | 'r10' | 'wet';

export default class ClimateGrid implements ClimateSource {
  readonly source: string;
  readonly years: [number, number];
  readonly cols: number;
  readonly rows: number;
  readonly lon0: number;
  readonly lat0: number;
  readonly step: number;
  private data: Record<ClimateVar, Float32Array[]>;
  /** Seasonal-curve coefficients per variable: TERMS values per cell. */
  private season: Partial<Record<SeasonVar, Float32Array>> = {};

  /** True when the grid has counted rainy days (ERA5-Land), not just CRU wet days. */
  readonly hasRainyDayCounts: boolean;
  /** True when the grid knows each cell's mean height, for altitude correction. */
  readonly hasElevation: boolean;

  /**
   * @param header grid geometry and how values are stored
   * @param buffer values laid out [variable][month][row][col]: uint8 with a
   *   per-variable encoding, or little-endian int16 divided by `scale`
   */
  constructor(header: ClimateHeader, buffer: ArrayBuffer) {
    this.source = header.source;
    this.years = header.years;
    this.cols = header.cols;
    this.rows = header.rows;
    this.lon0 = header.lon0;
    this.lat0 = header.lat0;
    this.step = header.step;
    const raw =
      header.dtype === 'u8' ? new Uint8Array(buffer) : new Int16Array(buffer);
    const cells = header.rows * header.cols;
    const data = {} as Record<ClimateVar, Float32Array[]>;
    header.vars.forEach((v, vi) => {
      const decode = decoder(header, v);
      data[v] = Array.from({ length: 12 }, (_, m) => {
        const out = new Float32Array(cells);
        const off = (vi * 12 + m) * cells;
        for (let i = 0; i < cells; i++) {
          const x = raw[off + i]!;
          out[i] = x === header.nodata ? Number.NaN : decode(x);
        }
        return out;
      });
    });
    (header.static ?? []).forEach((v, si) => {
      const decode = decoder(header, v);
      const out = new Float32Array(cells);
      const off = (header.vars.length * 12 + si) * cells;
      for (let i = 0; i < cells; i++) {
        const x = raw[off + i]!;
        out[i] = x === header.nodata ? Number.NaN : decode(x);
      }
      // The same values for every month, so sample() works unchanged.
      data[v] = Array.from({ length: 12 }, () => out);
    });
    this.data = data;
    this.hasRainyDayCounts = header.vars.includes('r5');
    this.hasElevation = (header.static ?? []).includes('elev');
    this.fitSeasons(header.vars, cells);
  }

  /**
   * Fit each cell's seasonal curve. Temperatures as they are; rain as mm per
   * day and rainy days as the share of days, so months of different lengths
   * compare fairly.
   */
  private fitSeasons(vars: ClimateVar[], cells: number): void {
    const monthly = new Array<number>(12);
    for (const v of vars) {
      if (v === 'elev') continue;
      const perDay = v !== 'tmx' && v !== 'tmn';
      const c = new Float32Array(cells * TERMS);
      for (let i = 0; i < cells; i++) {
        let ok = true;
        for (let m = 0; m < 12; m++) {
          const x = this.data[v][m]![i]!;
          if (Number.isNaN(x)) {
            ok = false;
            break;
          }
          monthly[m] = perDay ? x / DAYS_IN_MONTH[m]! : x;
        }
        if (ok) fitSeason(monthly, c, i * TERMS);
        else c[i * TERMS] = Number.NaN;
      }
      this.season[v] = c;
    }
  }

  /**
   * Smoothed value of one cell at a position in the year: °C for tmx/tmn,
   * mm per day for pre, share of days for r1/r5/r10/wet.
   */
  cellAt(v: SeasonVar, phase: number, row: number, col: number): number {
    if (row < 0 || col < 0 || row >= this.rows || col >= this.cols) {
      return Number.NaN;
    }
    const c = this.season[v];
    if (!c) return Number.NaN;
    const at = (row * this.cols + col) * TERMS;
    if (Number.isNaN(c[at]!)) return Number.NaN;
    return evalSeason(c, at, phase);
  }

  /** Bilinear sample of a smoothed value (see cellAt), coast-aware like sample(). */
  sampleAt(v: SeasonVar, phase: number, lat: number, lon: number): number {
    const fx = (lon - this.lon0) / this.step;
    const fy = (this.lat0 - lat) / this.step;
    const c0 = Math.floor(fx);
    const r0 = Math.floor(fy);
    const tx = fx - c0;
    const ty = fy - r0;
    let sum = 0;
    let wsum = 0;
    for (const [dr, dc, w] of [
      [0, 0, (1 - tx) * (1 - ty)],
      [0, 1, tx * (1 - ty)],
      [1, 0, (1 - tx) * ty],
      [1, 1, tx * ty],
    ] as const) {
      const val = this.cellAt(v, phase, r0 + dr, c0 + dc);
      if (!Number.isNaN(val) && w > 0) {
        sum += val * w;
        wsum += w;
      }
    }
    if (wsum > 0) return sum / wsum;
    const row = Math.round(fy);
    const col = Math.round(fx);
    for (let r = 1; r <= 2; r++) {
      for (let dr = -r; dr <= r; dr++) {
        for (let dc = -r; dc <= r; dc++) {
          const val = this.cellAt(v, phase, row + dr, col + dc);
          if (!Number.isNaN(val)) return val;
        }
      }
    }
    return Number.NaN;
  }

  /** Rainy-day share of one cell at a position in the year. */
  cellRainChanceAt(
    phase: number,
    row: number,
    col: number,
    threshold: number,
  ): number {
    const v: SeasonVar = this.hasRainyDayCounts
      ? (countVar(threshold) as SeasonVar)
      : 'wet';
    const share = this.cellAt(v, phase, row, col);
    if (this.hasRainyDayCounts || Number.isNaN(share)) return clamp01(share);
    // CRU grids: estimate from the smoothed rain rate and wet-day share.
    const days = 30.44;
    return clamp01(
      rainyDays(
        this.cellAt('pre', phase, row, col) * days,
        share * days,
        threshold,
      ) / days,
    );
  }

  /**
   * The weather at a point and a position in the year (0 … 1), from the
   * smooth seasonal curves. Monthly fields hold the rate at that moment
   * scaled to an average month (30.44 days).
   */
  at(
    phase: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    const shift = this.altitudeShiftAt(lat, lon, ele, phase);
    const rain = Math.max(0, this.sampleAt('pre', phase, lat, lon));
    let chance: number;
    if (this.hasRainyDayCounts) {
      chance = clamp01(
        this.sampleAt(countVar(threshold) as SeasonVar, phase, lat, lon),
      );
    } else {
      const days = 30.44;
      const wet = this.sampleAt('wet', phase, lat, lon) * days;
      chance = clamp01(rainyDays(rain * days, wet, threshold) / days);
    }
    return {
      high: this.sampleAt('tmx', phase, lat, lon) + shift,
      low: this.sampleAt('tmn', phase, lat, lon) + shift,
      rainMm: rain,
      rainChance: chance,
      monthRainMm: rain * 30.44,
      monthWetDays: chance * 30.44,
      altitudeShift: shift,
    };
  }

  get bounds(): [[number, number], [number, number]] {
    const h = this.step / 2;
    return [
      [this.lat0 - (this.rows - 1) * this.step - h, this.lon0 - h],
      [this.lat0 + h, this.lon0 + (this.cols - 1) * this.step + h],
    ];
  }

  /** Raw value of one cell (NaN over sea / outside the grid). */
  cell(v: ClimateVar, month: number, row: number, col: number): number {
    if (row < 0 || col < 0 || row >= this.rows || col >= this.cols) {
      return Number.NaN;
    }
    return this.data[v][month]![row * this.cols + col]!;
  }

  /**
   * Bilinear sample of one variable for a calendar month (0..11).
   * Missing neighbours (coast) are skipped, so coastal points still get a value.
   */
  sample(v: ClimateVar, month: number, lat: number, lon: number): number {
    const fx = (lon - this.lon0) / this.step;
    const fy = (this.lat0 - lat) / this.step;
    const c0 = Math.floor(fx);
    const r0 = Math.floor(fy);
    const tx = fx - c0;
    const ty = fy - r0;
    let sum = 0;
    let wsum = 0;
    for (const [dr, dc, w] of [
      [0, 0, (1 - tx) * (1 - ty)],
      [0, 1, tx * (1 - ty)],
      [1, 0, (1 - tx) * ty],
      [1, 1, tx * ty],
    ] as const) {
      const val = this.cell(v, month, r0 + dr, c0 + dc);
      if (!Number.isNaN(val) && w > 0) {
        sum += val * w;
        wsum += w;
      }
    }
    if (wsum > 0) return sum / wsum;
    // A point just off the coast: fall back to the nearest land cell nearby.
    return this.nearest(v, month, Math.round(fy), Math.round(fx));
  }

  private nearest(v: ClimateVar, month: number, row: number, col: number) {
    for (let r = 1; r <= 2; r++) {
      for (let dr = -r; dr <= r; dr++) {
        for (let dc = -r; dc <= r; dc++) {
          const val = this.cell(v, month, row + dr, col + dc);
          if (!Number.isNaN(val)) return val;
        }
      }
    }
    return Number.NaN;
  }

  /** Is there any data near this point? */
  covers(lat: number, lon: number): boolean {
    return !Number.isNaN(this.sample('tmx', 0, lat, lon));
  }

  /** The weather at mid-month (month 0–11), from the smooth seasonal curves. */
  month(
    month: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    return this.at(phaseOfMonth(month), lat, lon, threshold, ele);
  }

  /** °C to add at a position in the year for a point at `ele` m, compared with its grid cell's mean height. */
  altitudeShiftAt(
    lat: number,
    lon: number,
    ele: number | null | undefined,
    phase: number,
  ): number {
    if (!this.hasElevation || ele === null || ele === undefined) return 0;
    const cell = this.sample('elev', 0, lat, lon);
    if (Number.isNaN(cell)) return 0;
    return -lapseRateAt(phase) * (ele - cell);
  }

  /** °C to add in `month` (0–11) for a point at `ele` m, compared with its grid cell's mean height. */
  altitudeShift(
    lat: number,
    lon: number,
    ele: number | null | undefined,
    month: number,
  ): number {
    if (!this.hasElevation || ele === null || ele === undefined) return 0;
    const cell = this.sample('elev', 0, lat, lon);
    if (Number.isNaN(cell)) return 0;
    return -LAPSE_RATES[month]! * (ele - cell);
  }

  /** Rainy days in a month for one grid cell. */
  cellRainyDays(
    month: number,
    row: number,
    col: number,
    threshold: number,
  ): number {
    if (this.hasRainyDayCounts) {
      return this.cell(countVar(threshold), month, row, col);
    }
    const pre = this.cell('pre', month, row, col);
    if (Number.isNaN(pre)) return Number.NaN;
    return rainyDays(pre, this.cell('wet', month, row, col), threshold);
  }

  /** Expected weather on a specific date, from the smooth seasonal curves. */
  on(
    date: Date,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    return this.at(phaseOfDate(date), lat, lon, threshold, ele);
  }
}

// Colour scale for daytime temperatures, tuned for riding: blues are cold,
// the yellows and greens are comfortable, reds are hot.
export const TEMP_STOPS: [number, string][] = [
  [-15, '#2b2f73'],
  [-5, '#3f5fb0'],
  [0, '#78a6d6'],
  [5, '#b9dbe6'],
  [10, '#e8eec0'],
  [15, '#b9d97c'],
  [20, '#f2c14e'],
  [25, '#ec8a3a'],
  [30, '#d1452c'],
  [35, '#8e1b2a'],
];

function hexToRgb(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}
const TEMP_RGB = TEMP_STOPS.map(([t, c]) => [t, ...hexToRgb(c)] as const);

export function tempRgb(t: number): [number, number, number] {
  if (t <= TEMP_RGB[0]![0])
    return TEMP_RGB[0]!.slice(1) as [number, number, number];
  for (let i = 1; i < TEMP_RGB.length; i++) {
    const [t1, r1, g1, b1] = TEMP_RGB[i]!;
    if (t <= t1) {
      const [t0, r0, g0, b0] = TEMP_RGB[i - 1]!;
      const f = (t - t0) / (t1 - t0);
      return [r0 + (r1 - r0) * f, g0 + (g1 - g0) * f, b0 + (b1 - b0) * f];
    }
  }
  return TEMP_RGB[TEMP_RGB.length - 1]!.slice(1) as [number, number, number];
}

export function tempColor(t: number): string {
  const [r, g, b] = tempRgb(t);
  return `rgb(${Math.round(r)} ${Math.round(g)} ${Math.round(b)})`;
}

/** What the trip planner and the map read from: one grid or several combined. */
export interface ClimateSource {
  readonly years: [number, number];
  covers(lat: number, lon: number): boolean;
  month(
    month: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate;
  on(
    date: Date,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate;
  at(
    phase: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate;
}

const NO_DATA: DayClimate = {
  high: Number.NaN,
  low: Number.NaN,
  rainMm: Number.NaN,
  rainChance: Number.NaN,
  monthRainMm: Number.NaN,
  monthWetDays: Number.NaN,
  altitudeShift: 0,
};

/**
 * Several loaded continents as one climate. Every continent is cut from the
 * same worldwide grid, so where two overlap their values are identical: a
 * point is answered by the first grid that has data there.
 */
export class ClimateSet implements ClimateSource {
  constructor(readonly grids: ClimateGrid[]) {}

  get years(): [number, number] {
    return this.grids[0]?.years ?? [2011, 2025];
  }

  private gridAt(lat: number, lon: number): ClimateGrid | undefined {
    return this.grids.find((g) => g.covers(lat, lon));
  }

  covers(lat: number, lon: number): boolean {
    return this.gridAt(lat, lon) !== undefined;
  }

  month(
    month: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    return (
      this.gridAt(lat, lon)?.month(month, lat, lon, threshold, ele) ?? NO_DATA
    );
  }

  on(
    date: Date,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    return this.gridAt(lat, lon)?.on(date, lat, lon, threshold, ele) ?? NO_DATA;
  }

  at(
    phase: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    return (
      this.gridAt(lat, lon)?.at(phase, lat, lon, threshold, ele) ?? NO_DATA
    );
  }
}
