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

/** Standard lapse rate: air cools about 6.5 °C per 1,000 m of height. */
export const LAPSE_RATE = 0.0065;

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

export default class ClimateGrid {
  readonly source: string;
  readonly years: [number, number];
  readonly cols: number;
  readonly rows: number;
  readonly lon0: number;
  readonly lat0: number;
  readonly step: number;
  private data: Record<ClimateVar, Float32Array[]>;

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

  /** Monthly normals at a point (month 0..11); rainy days counted from `threshold` mm. */
  /**
   * Monthly normals at a point (month 0..11); rainy days counted from
   * `threshold` mm. With `ele` (m) and a grid that knows its cells' heights,
   * high and low are shifted by the lapse rate for the height difference.
   */
  month(
    month: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    const days = DAYS_IN_MONTH[month]!;
    const shift = this.altitudeShift(lat, lon, ele);
    const pre = this.sample('pre', month, lat, lon);
    const rainy = this.hasRainyDayCounts
      ? this.sample(countVar(threshold), month, lat, lon)
      : rainyDays(pre, this.sample('wet', month, lat, lon), threshold);
    return {
      high: this.sample('tmx', month, lat, lon) + shift,
      low: this.sample('tmn', month, lat, lon) + shift,
      rainMm: pre / days,
      rainChance: Number.isNaN(pre) ? Number.NaN : Math.min(1, rainy / days),
      monthRainMm: pre,
      monthWetDays: Number.isNaN(pre) ? Number.NaN : rainy,
      altitudeShift: shift,
    };
  }

  /** °C to add for a point at `ele` m compared with its grid cell's mean height. */
  altitudeShift(lat: number, lon: number, ele?: number | null): number {
    if (!this.hasElevation || ele === null || ele === undefined) return 0;
    const cell = this.sample('elev', 0, lat, lon);
    if (Number.isNaN(cell)) return 0;
    return -LAPSE_RATE * (ele - cell);
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

  /**
   * Expected weather on a specific date. Monthly means are treated as values at
   * mid-month and interpolated linearly in between, so 31 Jan is about halfway
   * between January and February.
   */
  on(
    date: Date,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    const m = date.getMonth();
    const mid = DAYS_IN_MONTH[m]! / 2;
    const day = date.getDate() - 0.5;
    let m2: number;
    let t: number;
    if (day < mid) {
      m2 = (m + 11) % 12;
      t = (mid - day) / ((DAYS_IN_MONTH[m2]! + DAYS_IN_MONTH[m]!) / 2);
    } else {
      m2 = (m + 1) % 12;
      t = (day - mid) / ((DAYS_IN_MONTH[m]! + DAYS_IN_MONTH[m2]!) / 2);
    }
    const a = this.month(m, lat, lon, threshold, ele);
    const b = this.month(m2, lat, lon, threshold, ele);
    const mix = (x: number, y: number) => x + (y - x) * t;
    return {
      high: mix(a.high, b.high),
      low: mix(a.low, b.low),
      rainMm: mix(a.rainMm, b.rainMm),
      rainChance: mix(a.rainChance, b.rainChance),
      monthRainMm: a.monthRainMm,
      monthWetDays: a.monthWetDays,
      altitudeShift: a.altitudeShift,
    };
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
