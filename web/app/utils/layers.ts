// Renders the climate grid into Web-Mercator canvases for Leaflet image overlays.
// The grid is regular in latitude, the map is not, so every output row is
// re-projected rather than stretching the grid image.

import type ClimateGrid from './climate';
import { DAYS_PER_MONTH, tempRgb, type RainThreshold } from './climate';
import type {
  CityLimit,
  RainMetric,
  TempMetric,
} from 'forkcast/services/planner';

const R = 6378137;
const toY = (lat: number) =>
  R * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
const toLat = (y: number) =>
  (2 * Math.atan(Math.exp(y / R)) - Math.PI / 2) * (180 / Math.PI);

export interface Raster {
  url: string;
  bounds: [[number, number], [number, number]];
}

/** The Web-Mercator canvas over a grid's own area, at about 3 pixels per cell (at most 12 per degree). */
function frame(grid: ClimateGrid) {
  const pxPerDeg = Math.min(12, 3 / grid.step);
  const [[south, west], [north, east]] = grid.area;
  const width = Math.round((east - west) * pxPerDeg);
  const yN = toY(north);
  const yS = toY(south);
  const height = Math.round(((yN - yS) / R) * (180 / Math.PI) * pxPerDeg);
  return { south, west, north, east, width, height, yN, yS };
}

/**
 * Draw one value per map pixel over the land cells of a grid's own area, in
 * Web-Mercator rows. `pixel` gets the point and the grid's fractional row and
 * column, and returns an RGBA colour or null to leave the pixel clear.
 */
function rasterize(
  grid: ClimateGrid,
  pixel: (
    lat: number,
    lon: number,
    fy: number,
    fx: number,
  ) => [number, number, number, number] | null,
): Raster {
  const f = frame(grid);
  const canvas = document.createElement('canvas');
  canvas.width = f.width;
  canvas.height = f.height;
  const ctx = canvas.getContext('2d')!;
  const img = ctx.createImageData(f.width, f.height);
  for (let py = 0; py < f.height; py++) {
    const lat = toLat(f.yN - ((py + 0.5) / f.height) * (f.yN - f.yS));
    const fy = (grid.lat0 - lat) / grid.step;
    for (let px = 0; px < f.width; px++) {
      const lon = f.west + ((px + 0.5) / f.width) * (f.east - f.west);
      const fx = (lon - grid.lon0) / grid.step;
      // Inside a land cell only (no coastal extrapolation).
      if (!grid.isLand(Math.round(fy), Math.round(fx))) continue;
      const rgba = pixel(lat, lon, fy, fx);
      if (!rgba) continue;
      img.data.set(rgba, (py * f.width + px) * 4);
    }
  }
  ctx.putImageData(img, 0, 0);
  return {
    url: canvas.toDataURL(),
    bounds: [
      [f.south, f.west],
      [f.north, f.east],
    ],
  };
}

/** Smooth temperature field, transparent over the sea. */
export function temperatureRaster(
  grid: ClimateGrid,
  /** Position in the year, 0 … 1 */
  phase: number,
  metric: TempMetric,
): Raster {
  const v = metric === 'high' ? 'tmx' : 'tmn';
  return rasterize(grid, (lat, lon) => {
    const [r, g, b] = tempRgb(grid.sampleAt(v, phase, lat, lon));
    return [r, g, b, 215];
  });
}

// Relief: hillshading from the grid's terrain height, lit from the north-west
// at 45°. The cells are about 25 km, so slopes are exaggerated to show.
const RELIEF_EXAGGERATION = 10;
const LIGHT = (() => {
  const alt = Math.PI / 4;
  const az = (315 * Math.PI) / 180; // from the north-west
  return [
    Math.sin(az) * Math.cos(alt),
    Math.cos(az) * Math.cos(alt),
    Math.sin(alt),
  ];
})();
const shades = new WeakMap<ClimateGrid, Float32Array>();

/** How lit each cell is: 1 on flat ground and slopes facing the light, less in shade. */
function cellShades(grid: ClimateGrid): Float32Array {
  let out = shades.get(grid);
  if (out) return out;
  out = new Float32Array(grid.rows * grid.cols).fill(Number.NaN);
  const e = (r: number, c: number) => grid.elevation(r, c);
  for (let r = 0; r < grid.rows; r++) {
    const lat = grid.lat0 - r * grid.step;
    const dx = grid.step * 111320 * Math.cos((lat * Math.PI) / 180) * 2;
    const dy = grid.step * 110540 * 2;
    for (let c = 0; c < grid.cols; c++) {
      const h = e(r, c);
      if (Number.isNaN(h)) continue;
      const at = (v: number) => (Number.isNaN(v) ? h : v);
      const dzdx = (at(e(r, c + 1)) - at(e(r, c - 1))) / dx;
      const dzdy = (at(e(r - 1, c)) - at(e(r + 1, c))) / dy; // north is up
      const nx = -RELIEF_EXAGGERATION * dzdx;
      const ny = -RELIEF_EXAGGERATION * dzdy;
      const lit =
        (nx * LIGHT[0]! + ny * LIGHT[1]! + LIGHT[2]!) / Math.hypot(nx, ny, 1);
      out[r * grid.cols + c] = Math.min(1, Math.max(0, lit / LIGHT[2]!));
    }
  }
  shades.set(grid, out);
  return out;
}

/**
 * Relief shading, drawn in greys that only darken (the map pane multiplies it
 * onto the colours below), bilinear between cells, transparent over the sea.
 */
export function reliefRaster(grid: ClimateGrid): Raster {
  const shade = cellShades(grid);
  const at = (r: number, c: number) =>
    r < 0 || c < 0 || r >= grid.rows || c >= grid.cols
      ? Number.NaN
      : shade[r * grid.cols + c]!;
  return rasterize(grid, (_lat, _lon, fy, fx) => {
    const r0 = Math.floor(fy);
    const c0 = Math.floor(fx);
    let sum = 0;
    let weight = 0;
    for (const [r, c, w] of [
      [r0, c0, (1 - (fy - r0)) * (1 - (fx - c0))],
      [r0, c0 + 1, (1 - (fy - r0)) * (fx - c0)],
      [r0 + 1, c0, (fy - r0) * (1 - (fx - c0))],
      [r0 + 1, c0 + 1, (fy - r0) * (fx - c0)],
    ] as const) {
      const v = at(r, c);
      if (!Number.isNaN(v)) {
        sum += v * w;
        weight += w;
      }
    }
    if (!weight) return null;
    const g = 255 * (1 - (1 - sum / weight) * 0.75);
    return [g, g, g, 255];
  });
}

/** A rain dot fills its cell at this much in an average month (mm, or rainy days). */
export const DOT_FULL = { mm: 250, days: 20 } as const;

export interface RainDot {
  lat: number;
  lon: number;
  /** Radius in metres, so the dot keeps its size relative to the land at any zoom */
  radius: number;
}

/**
 * Rain as dots, one per grid cell: area proportional to the rain (or the
 * chance of a rainy day) at that time of year, so it reads on top of the
 * temperatures. The legend gives the sizes as amounts in the week shown.
 */
export function rainDots(
  grid: ClimateGrid,
  /** Position in the year, 0 … 1 */
  phase: number,
  metric: RainMetric,
  threshold: number,
  /** Merge block × block cells into one dot (their average), for zoomed-out views */
  block = 1,
): RainDot[] {
  const full = DOT_FULL[metric];
  const cellM = (grid.step * Math.PI * 6371000) / 180;
  // Rates at this moment, scaled to an average month.
  const value = (row: number, col: number) =>
    (metric === 'mm'
      ? Math.max(0, grid.cellAt('pre', phase, row, col))
      : grid.cellRainChanceAt(phase, row, col, threshold)) * DAYS_PER_MONTH;
  return blocks(grid, block, value).map(({ lat, lon, val }) => {
    const half =
      (cellM * block * Math.min(1, Math.cos((lat * Math.PI) / 180))) / 2;
    return {
      lat,
      lon,
      radius: half * Math.sqrt(Math.min(1.3, val / full)) * 0.85,
    };
  });
}

/** The rain emoji, wettest last, each a little bigger. */
const EMOJI = [
  { emoji: '🌦️', px: 14 },
  { emoji: '🌧️', px: 18 },
  { emoji: '☔', px: 22 },
];

/**
 * Rainy days a week from which each emoji shows, per rainy-day threshold
 * (mm). Fewer than one a week shows nothing, so dry regions stay clear. The
 * heavier the threshold, the rarer such days (at 5 mm no part of Europe gets
 * 4 a week), so each threshold gets steps that its rain actually reaches.
 */
const EMOJI_STEPS: Record<RainThreshold, number[]> = {
  1: [1, 2, 3],
  5: [1, 1.5, 2],
  10: [1, 1.5],
};

export interface RainEmojiTier {
  min: number;
  emoji: string;
  px: number;
  /** "1–1½", or "2+ days" for the last */
  label: string;
}

const fmtDays = (n: number) =>
  Number.isInteger(n) ? String(n) : `${Math.floor(n)}½`;

/** The emoji steps for a rainy-day threshold, as the map and the legend use them. */
export function rainEmojiTiers(threshold: number): RainEmojiTier[] {
  const steps = EMOJI_STEPS[threshold as RainThreshold] ?? EMOJI_STEPS[5];
  return steps.map((min, i) => {
    const next = steps[i + 1];
    return {
      min,
      ...EMOJI[i]!,
      label: next
        ? `${fmtDays(min)}–${fmtDays(next)}`
        : `${fmtDays(min)}+ days`,
    };
  });
}

/** The emoji tier for this many rainy days a week, if any. */
export function rainEmojiTier(
  daysAWeek: number,
  threshold: number,
): RainEmojiTier | undefined {
  return rainEmojiTiers(threshold).findLast((t) => daysAWeek >= t.min);
}

export interface RainMark {
  lat: number;
  lon: number;
  tier: RainEmojiTier;
}

/**
 * Rainy days a week as emoji, one per block of cells (their average) where
 * there is at least one; the tiers are rainEmojiTiers.
 */
export function rainMarks(
  grid: ClimateGrid,
  /** Position in the year, 0 … 1 */
  phase: number,
  threshold: number,
  block = 1,
): RainMark[] {
  const value = (row: number, col: number) =>
    grid.cellRainChanceAt(phase, row, col, threshold) * 7;
  return blocks(grid, block, value).flatMap(({ lat, lon, val }) => {
    const tier = rainEmojiTier(val, threshold);
    return tier ? [{ lat, lon, tier }] : [];
  });
}

export interface WindArrow {
  lat: number;
  lon: number;
  /** The wind in the strongest riding hour: its speed, m/s */
  speed: number;
  /** Its mean wind vector, m/s toward the east and the north */
  u: number;
  v: number;
  /** How steady it is, its cells' windSteadiness averaged: 0 … 1 */
  steadiness: number;
}

/** The strongest riding hour's wind, one arrow per block of cells (their average). */
export function windArrows(
  grid: ClimateGrid,
  /** Position in the year, 0 … 1 */
  phase: number,
  block = 1,
): WindArrow[] {
  const comp = (name: 'wspd' | 'u10' | 'v10') =>
    blocks(grid, block, (r, c) => grid.cellAt(name, phase, r, c), false);
  const u = comp('u10');
  const v = comp('v10');
  // Each cell's own steadiness, averaged: the block's mean vector would
  // shrink wherever neighbouring winds blow different ways.
  const steadiness = blocks(
    grid,
    block,
    (r, c) =>
      Math.hypot(
        grid.cellAt('u10', phase, r, c),
        grid.cellAt('v10', phase, r, c),
      ) / grid.cellAt('wspd', phase, r, c),
    false,
  );
  return comp('wspd').map((s, i) => ({
    lat: s.lat,
    lon: s.lon,
    speed: s.val,
    u: u[i]!.val,
    v: v[i]!.val,
    steadiness: steadiness[i]!.val,
  }));
}

/**
 * The average of `value` over block × block cells, at the centre of each
 * block in the grid's own area. Blocks are aligned to the worldwide grid, not
 * to this tile's corner, so neighbouring tiles merge cells into the same
 * pattern. Only positive averages unless `positiveOnly` is false.
 */
function blocks(
  grid: ClimateGrid,
  block: number,
  value: (row: number, col: number) => number,
  positiveOnly = true,
): { lat: number; lon: number; val: number }[] {
  const out: { lat: number; lon: number; val: number }[] = [];
  const rowStart = -(Math.round((90 - grid.lat0) / grid.step) % block);
  const colStart = -(Math.round((grid.lon0 + 180) / grid.step) % block);
  for (let r0 = rowStart; r0 < grid.rows; r0 += block) {
    for (let c0 = colStart; c0 < grid.cols; c0 += block) {
      let sum = 0;
      let n = 0;
      for (let r = Math.max(0, r0); r < Math.min(grid.rows, r0 + block); r++) {
        for (
          let c = Math.max(0, c0);
          c < Math.min(grid.cols, c0 + block);
          c++
        ) {
          const v = value(r, c);
          if (!Number.isNaN(v)) {
            sum += v;
            n++;
          }
        }
      }
      // Skip mostly-sea blocks so coasts don't sprout dots offshore.
      if (n === 0 || n < (block * block) / 3) continue;
      const val = sum / n;
      if (positiveOnly && val <= 0) continue;
      const lat = grid.lat0 - (r0 + (block - 1) / 2) * grid.step;
      const lonC = grid.lon0 + (c0 + (block - 1) / 2) * grid.step;
      if (!grid.owns(lat, lonC)) continue;
      out.push({ lat, lon: lonC, val });
    }
  }
  return out;
}

/** City names: the biggest this many per country, or every town of this many people. */
const TOP_CITIES = 10;
const BIG_CITY = 500_000;

/** Below this zoom (a few countries or more in view) only the capitals keep their names:
 * the full list would be a blur. */
const CAPITALS_ONLY_BELOW = 6;

export const isCapitalsOnly = (zoom: number): boolean =>
  zoom < CAPITALS_ONLY_BELOW;

/**
 * Does a town get its name on the map, with this city setting at this zoom?
 * Capitals always do (unless names are off), so one never disappears as you
 * zoom in.
 */
export function isPlaceShown(
  limit: CityLimit,
  zoom: number,
  pop: number,
  /** Its place by size in its country, 1 for the biggest */
  rank: number,
  isCapital: boolean,
): boolean {
  if (limit === 'off') return false;
  if (isCapital) return true;
  if (isCapitalsOnly(zoom)) return false;
  return limit === 'big' ? pop >= BIG_CITY : rank <= TOP_CITIES;
}

/** Below this, km/h, the map draws no wind. */
export const CALM_KMH = 10;

/**
 * Colours for wind speeds, km/h: white from CALM_KMH to a bright purple from
 * 25 km/h. The windiest hour, averaged over a month's days, rarely tops that:
 * 99% of Europe's land is under 24 km/h, 97% under 20.
 */
export const WIND_STOPS: [number, string][] = [
  [CALM_KMH, '#ffffff'],
  [25, '#b026ff'],
];

/** The colour of a wind of `kmh`, along WIND_STOPS (stronger: its last colour). */
export function windColor(kmh: number): string {
  const rgb = (hex: string) => {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  const last = WIND_STOPS[WIND_STOPS.length - 1]!;
  if (!(kmh < last[0])) return last[1];
  for (let i = 1; i < WIND_STOPS.length; i++) {
    const [k1, c1] = WIND_STOPS[i]!;
    if (kmh <= k1) {
      const [k0, c0] = WIND_STOPS[i - 1]!;
      const f = Math.max(0, (kmh - k0) / (k1 - k0));
      const a = rgb(c0);
      const b = rgb(c1);
      const [r, g, bl] = a.map((x, j) => Math.round(x + (b[j]! - x) * f));
      return `rgb(${r} ${g} ${bl})`;
    }
  }
  return last[1];
}
