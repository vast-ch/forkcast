// Climate normals on a regular lat/lon grid, as smooth seasonal curves, in 10°
// tiles (built by data/forkcast_data/era5land.py
// and variants.py, packed into curves and tiles by pack.py).

import { isMissing } from './helpers';

/** How a stored byte maps to a value. */
export type Encoding =
  | { kind: 'linear'; scale: number; offset: number; relative?: boolean }
  | { kind: 'sqrt'; scale: number };

/** Where a grid's cells are. */
export interface GridGeometry {
  lon0: number; // centre of the first column
  lat0: number; // centre of the first (northernmost) row
  step: number;
  cols: number;
  rows: number;
}

/**
 * Header of a climate (data/out/climate/<climate>.json): what its tiles hold
 * and how their bytes are read.
 */
export interface ClimateHeader {
  source: string;
  /** The period averaged; for a variant, the period it is a correction of */
  years: [number, number];
  /** A variant's id (data/forkcast_data/variants.py) */
  variant?: string;
  /** The last 10 or 5 years: the years averaged */
  window?: [number, number];
  /** El Niño or La Niña: the years its correction was measured over, and how many event months they hold */
  enso?: { years: [number, number]; months: number };
  /** Cell size of the tiles, degrees */
  step: number;
  /** Tile size, degrees; tiles start at multiples of it */
  tile: number;
  /** Cells along a tile's side: its edges' cells are in both neighbours */
  size: number;
  /** The tiles there are (where there is land), by id (see tileId) */
  tiles: string[];
  /** One byte per value, decoded with `encoding` */
  dtype: 'u8';
  /** Layers stored as seasonal curves, as many terms each as its encoding lists */
  vars: SeasonVar[];
  /** The most terms a layer has (TERMS); a layer's missing waves are 0 */
  terms: number;
  /** Layers without seasons, stored after the curves. */
  static?: 'elev'[];
  /** A curve's encoding per term; a "relative" term is a share of the curve's mean */
  encoding: Partial<Record<SeasonVar, Encoding[]>> & { elev?: Encoding };
  /** In every term of a cell without data (sea) */
  nodata: number;
}

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
  /** How far single days' highs stray from `high`: a standard deviation, °C (NaN if unknown) */
  highSpread: number;
  /** The same for the lows */
  lowSpread: number;
  /** The wind in the strongest riding hour of the day, on average: its speed, m/s (NaN if unknown) */
  windSpeed: number;
  /** Its mean wind vector, m/s toward the east and toward the north: which way it pushes, and how steadily (see windSteadiness) */
  windU: number;
  windV: number;
  /** Mean precipitation per day, mm */
  rainMm: number;
  /** Chance of a rainy day (at least the chosen threshold of rain), 0..1 */
  rainChance: number;
  /**
   * Mean rain on a day with at least 1 mm, mm: what a day brings when it
   * rains. NaN where rain is too rare to say.
   */
  wetDayMm: number;
  /** °C added to high and low for the point's height versus its grid cell (0 if unknown) */
  altitudeShift: number;
}

/** The climates a rider can pick: the 2011–2025 grid, and the variants data/forkcast_data/variants.py builds. */
export const CLIMATES = [
  'last15',
  'last10',
  'last5',
  'last1',
  'elnino',
  'lanina',
] as const;
export type ClimateId = (typeof CLIMATES)[number];

/** Rain thresholds offered for counting a day as rainy, mm. */
export const RAIN_THRESHOLDS = [1, 5, 10] as const;
export type RainThreshold = (typeof RAIN_THRESHOLDS)[number];

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

/** Days in an average month, to turn daily rates into monthly figures. */
export const DAYS_PER_MONTH = 30.44;

function clamp01(x: number): number {
  return Number.isNaN(x) ? x : Math.min(1, Math.max(0, x));
}

/**
 * Below this share of days with rain (about one in 50), rain per wet day is
 * left out: it would rest on a handful of days.
 */
const MIN_WET_SHARE = 0.02;

/** Compass points, clockwise from north. */
const COMPASS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'] as const;

/**
 * How steadily the wind blows from one side: the mean vector's length against
 * the mean speed, 1 when always from the same side, near 0 when from every
 * side in turn (NaN if unknown).
 */
export function windSteadiness(day: DayClimate): number {
  return Math.min(1, Math.hypot(day.windU, day.windV) / day.windSpeed);
}

/** Below this steadiness the wind blows from all sides: no direction to show. */
export const STEADY = 0.4;

/** Where a wind blowing toward (u east, v north) comes from: "SW". */
export function windFrom(u: number, v: number): string {
  const toward = (Math.atan2(u, v) * 180) / Math.PI; // clockwise from north
  const from = (toward + 180 + 360) % 360;
  return COMPASS[Math.round(from / 45) % 8]!;
}

/** The stored rainy-day count for a threshold (1, 5 or 10 mm). */
function countVar(threshold: number): SeasonVar {
  return threshold <= 1 ? 'r1' : threshold >= 10 ? 'r10' : 'r5';
}

function decode(e: Encoding | undefined, x: number): number {
  if (e?.kind === 'sqrt') return (x / e.scale) ** 2;
  if (e?.kind === 'linear') return x / e.scale + e.offset;
  return x;
}

/**
 * Number of yearly waves in the seasonal curve: 12-, 6- and 4-month cycles.
 * A curve is stored as its mean, then cos and sin of each wave.
 */
const HARMONICS = 3;
const TERMS = 1 + 2 * HARMONICS;

/** Position in the year, 0 … 1 (0 = 1 January 00:00). */
export function phaseOfDate(date: Date): number {
  const start = new Date(date.getFullYear(), 0, 1);
  const end = new Date(date.getFullYear() + 1, 0, 1);
  return (date.getTime() - start.getTime()) / (end.getTime() - start.getTime());
}

function evalSeason(c: Float32Array, at: number, phase: number): number {
  let v = c[at]!;
  for (let k = 1; k <= HARMONICS; k++) {
    const t = 2 * Math.PI * k * phase;
    v += c[at + 2 * k - 1]! * Math.cos(t) + c[at + 2 * k]! * Math.sin(t);
  }
  return v;
}

/** Lapse rate (°C per m) at a position in the year, blended between mid-month values. */
export function lapseRateAt(phase: number): number {
  const x = phase * 12 - 0.5;
  const m0 = Math.floor(x);
  const t = x - m0;
  const a = LAPSE_RATES[((m0 % 12) + 12) % 12]!;
  const b = LAPSE_RATES[(((m0 + 1) % 12) + 12) % 12]!;
  return a + (b - a) * t;
}

/**
 * The seasonal curves: tmx/tmn the mean daily max/min, °C; pre the rain, mm
 * per day; r1/r5/r10 the share of days with at least 1/5/10 mm; tmxsd/tmnsd
 * how far single days' max/min stray from their mean (a standard deviation, °C);
 * wspd the wind speed in the strongest riding hour, m/s, and u10/v10 that
 * hour's mean wind vector, m/s toward the east and north (see
 * data/forkcast_data/wind.py).
 */
type SeasonVar =
  | 'tmx'
  | 'tmn'
  | 'pre'
  | 'r1'
  | 'r5'
  | 'r10'
  | 'tmxsd'
  | 'tmnsd'
  | 'wspd'
  | 'u10'
  | 'v10';

/** 8 days in 10 fall within this many standard deviations of the mean (normal distribution). */
const USUAL_Z = 1.2816;

/** The range 8 days in 10 fall within: a mean ± USUAL_Z spreads. */
export function usualRange(mean: number, spread: number): [number, number] {
  return [mean - USUAL_Z * spread, mean + USUAL_Z * spread];
}

export default class ClimateGrid implements ClimateSource {
  readonly source: string;
  readonly years: [number, number];
  readonly cols: number;
  readonly rows: number;
  readonly lon0: number;
  readonly lat0: number;
  readonly step: number;
  /** The area this grid answers for, [[south, west], [north, east]]: a tile's own square (its edge cells are shared with its neighbours) */
  readonly area: [[number, number], [number, number]];
  /** Seasonal-curve coefficients per variable: TERMS values per cell, NaN at sea. */
  private season: Partial<Record<SeasonVar, Float32Array>> = {};
  /** Each cell's mean height, m (NaN at sea), if the grid has it */
  private elev?: Float32Array;

  /**
   * @param header how values are stored
   * @param geometry where the cells are
   * @param buffer one byte per value, laid out [variable][term][row][col]
   *   (each variable with the terms its encoding lists), then the static
   *   layers [variable][row][col]
   * @param area what the grid answers for, if not all of it
   */
  constructor(
    header: ClimateHeader,
    geometry: GridGeometry,
    buffer: ArrayBuffer,
    area?: [[number, number], [number, number]],
  ) {
    this.source = header.source;
    this.years = header.years;
    this.cols = geometry.cols;
    this.rows = geometry.rows;
    this.lon0 = geometry.lon0;
    this.lat0 = geometry.lat0;
    this.step = geometry.step;
    this.area = area ?? this.bounds;
    if (header.terms !== TERMS)
      throw new Error(`Climate grid has ${header.terms} terms, not ${TERMS}`);
    const raw = new Uint8Array(buffer);
    const cells = this.rows * this.cols;
    let first = 0; // the layer's first byte
    for (const v of header.vars) {
      const encodings = header.encoding[v] ?? [];
      const c = new Float32Array(cells * TERMS);
      for (let i = 0; i < cells; i++) {
        const at = first + i;
        if (raw[at] === header.nodata) {
          c[i * TERMS] = Number.NaN;
          continue;
        }
        const mean = decode(encodings[0], raw[at]!);
        c[i * TERMS] = mean;
        for (let t = 1; t < encodings.length; t++) {
          const e = encodings[t];
          const x = decode(e, raw[at + t * cells]!);
          c[i * TERMS + t] = e?.kind === 'linear' && e.relative ? x * mean : x;
        }
      }
      this.season[v] = c;
      first += encodings.length * cells;
    }
    const statics = header.static ?? [];
    const e = statics.indexOf('elev');
    if (e >= 0) {
      const off = first + e * cells;
      this.elev = new Float32Array(cells);
      for (let i = 0; i < cells; i++) {
        const x = raw[off + i]!;
        this.elev[i] =
          x === header.nodata ? Number.NaN : decode(header.encoding.elev, x);
      }
    }
  }

  /** True when the grid knows each cell's mean height, for altitude correction. */
  get hasElevation(): boolean {
    return this.elev !== undefined;
  }

  private index(row: number, col: number): number {
    return row < 0 || col < 0 || row >= this.rows || col >= this.cols
      ? -1
      : row * this.cols + col;
  }

  /** Is the point in the grid's own area (south and west edges included)? */
  owns(lat: number, lon: number): boolean {
    const [[s, w], [n, e]] = this.area;
    return lat >= s && lat < n && lon >= w && lon < e;
  }

  /** Does this cell have data (land)? */
  isLand(row: number, col: number): boolean {
    const i = this.index(row, col);
    return i >= 0 && !Number.isNaN(this.season.tmx?.[i * TERMS] ?? Number.NaN);
  }

  /** A cell's mean height, m (NaN at sea, outside the grid or unknown). */
  elevation(row: number, col: number): number {
    const i = this.index(row, col);
    return i >= 0 && this.elev ? this.elev[i]! : Number.NaN;
  }

  /**
   * Smoothed value of one cell at a position in the year: °C for tmx/tmn,
   * mm per day for pre, share of days for r1/r5/r10.
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

  /** Rainy-day share of one cell at a position in the year. */
  cellRainChanceAt(
    phase: number,
    row: number,
    col: number,
    threshold: number,
  ): number {
    return clamp01(this.cellAt(countVar(threshold), phase, row, col));
  }

  /**
   * Bilinear interpolation of `value(row, col)` at a point. Missing
   * neighbours (coast) are skipped, so coastal points still get a value; a
   * point just off the coast falls back to the nearest land cell nearby.
   */
  private interpolate(
    lat: number,
    lon: number,
    value: (row: number, col: number) => number,
  ): number {
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
      const val = value(r0 + dr, c0 + dc);
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
          const val = value(row + dr, col + dc);
          if (!Number.isNaN(val)) return val;
        }
      }
    }
    return Number.NaN;
  }

  /** A smoothed value (see cellAt) at a point (see interpolate). */
  sampleAt(v: SeasonVar, phase: number, lat: number, lon: number): number {
    return this.interpolate(lat, lon, (r, c) => this.cellAt(v, phase, r, c));
  }

  /** Is there any data near this point? */
  covers(lat: number, lon: number): boolean {
    return !Number.isNaN(this.sampleAt('tmx', 0, lat, lon));
  }

  /** °C to add at a position in the year for a point at `ele` m, compared with its grid cell's mean height. */
  altitudeShiftAt(
    lat: number,
    lon: number,
    ele: number | null | undefined,
    phase: number,
  ): number {
    if (!this.hasElevation || ele === null || ele === undefined) return 0;
    const cell = this.interpolate(lat, lon, (r, c) => this.elevation(r, c));
    if (Number.isNaN(cell)) return 0;
    return -lapseRateAt(phase) * (ele - cell);
  }

  /**
   * The weather at a point and a position in the year (0 … 1), from the
   * smooth seasonal curves. Monthly fields hold the rate at that moment
   * scaled to an average month.
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
    const chance = clamp01(this.sampleAt(countVar(threshold), phase, lat, lon));
    // The rain over the days with rain: the average spread over dry
    // days too would say little about what a wet day is like.
    const wet =
      threshold <= 1 ? chance : clamp01(this.sampleAt('r1', phase, lat, lon));
    return {
      high: this.sampleAt('tmx', phase, lat, lon) + shift,
      low: this.sampleAt('tmn', phase, lat, lon) + shift,
      highSpread: this.sampleAt('tmxsd', phase, lat, lon),
      lowSpread: this.sampleAt('tmnsd', phase, lat, lon),
      windSpeed: this.sampleAt('wspd', phase, lat, lon),
      windU: this.sampleAt('u10', phase, lat, lon),
      windV: this.sampleAt('v10', phase, lat, lon),
      rainMm: rain,
      rainChance: chance,
      wetDayMm: wet >= MIN_WET_SHARE ? rain / wet : Number.NaN,
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

/** Text colour that reads on a temperature's colour: white on the dark blues
 * and reds, ink on the light greens and yellows. */
export function tempInk(t: number | null | undefined): string {
  if (isMissing(t)) return 'var(--wt-ink)';
  const [r, g, b] = tempRgb(t);
  const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return luminance < 0.55 ? '#fff' : 'var(--wt-ink)';
}

/** Colour of a temperature, or `fallback` when there is none (no data). */
export function tempSwatch(
  t: number | null | undefined,
  fallback = 'transparent',
): string {
  return isMissing(t) ? fallback : tempColor(t);
}

/** What the trip planner and the map read from: one grid or several combined. */
export interface ClimateSource {
  readonly years: [number, number];
  covers(lat: number, lon: number): boolean;
  /** The weather at a point and a position in the year (0 … 1). */
  at(
    phase: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate;
}

/** Expected weather on a specific date at a route point. */
export function climateOn(
  climate: ClimateSource,
  date: Date,
  p: { lat: number; lon: number; ele?: number | null },
  threshold: number,
): DayClimate {
  return climate.at(phaseOfDate(date), p.lat, p.lon, threshold, p.ele);
}

/** The tile a point is in, by its south-west corner: "40_10" for 40–50° N, 10–20° E. */
export function tileId(lat: number, lon: number, tile = 10): string {
  const x = ((((lon + 180) % 360) + 360) % 360) - 180;
  return `${Math.floor(lat / tile) * tile}_${Math.floor(x / tile) * tile}`;
}

/** The ids of every tile overlapping a box (they may not all exist). */
export function tilesIn(
  [[south, west], [north, east]]: [[number, number], [number, number]],
  tile = 10,
): string[] {
  const ids: string[] = [];
  const s = Math.max(-90, Math.floor(south / tile) * tile);
  const n = Math.min(90, north);
  const w = Math.floor(west / tile) * tile;
  const e = Math.min(east, w + 360);
  for (let lat = s; lat < n; lat += tile)
    for (let lon = w; lon < e; lon += tile) ids.push(tileId(lat, lon, tile));
  return [...new Set(ids)];
}

/** The tiles a line of points passes through. */
export function tilesAlong(
  line: { points: readonly { lat: number; lon: number }[] },
  tile = 10,
): string[] {
  return [...new Set(line.points.map((p) => tileId(p.lat, p.lon, tile)))];
}

/** A tile's own square, [[south, west], [north, east]]. */
export function tileArea(
  id: string,
  tile = 10,
): [[number, number], [number, number]] {
  const [lat, lon] = id.split('_').map(Number) as [number, number];
  return [
    [lat, lon],
    [lat + tile, lon + tile],
  ];
}

/** A day where no tile is loaded: nothing known. */
const UNKNOWN: DayClimate = {
  high: Number.NaN,
  low: Number.NaN,
  highSpread: Number.NaN,
  lowSpread: Number.NaN,
  rainMm: Number.NaN,
  rainChance: Number.NaN,
  wetDayMm: Number.NaN,
  altitudeShift: 0,
  windSpeed: Number.NaN,
  windU: Number.NaN,
  windV: Number.NaN,
};

/**
 * One climate as the trip and the map read it: the tiles loaded so far.
 * Where none is, nothing is known (NaN) until it arrives.
 */
export class TiledClimate implements ClimateSource {
  constructor(
    readonly header: ClimateHeader,
    readonly tiles: ReadonlyMap<string, ClimateGrid>,
  ) {}

  get years(): [number, number] {
    return this.header.years;
  }

  /** The tile of a point, if loaded. */
  gridAt(lat: number, lon: number): ClimateGrid | undefined {
    return this.tiles.get(tileId(lat, lon, this.header.tile));
  }

  covers(lat: number, lon: number): boolean {
    return this.gridAt(lat, lon)?.covers(lat, lon) ?? false;
  }

  at(
    phase: number,
    lat: number,
    lon: number,
    threshold: number,
    ele?: number | null,
  ): DayClimate {
    return (
      this.gridAt(lat, lon)?.at(phase, lat, lon, threshold, ele) ?? UNKNOWN
    );
  }
}
