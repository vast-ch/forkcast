// Renders the climate grid into Web-Mercator canvases for Leaflet image overlays.
// The grid is regular in latitude, the map is not, so every output row is
// re-projected rather than stretching the grid image.

import type ClimateGrid from './climate';
import { tempRgb } from './climate';
import type { RainMetric, TempMetric } from 'forkcast/services/planner';

const R = 6378137;
const toY = (lat: number) =>
  R * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
const toLat = (y: number) =>
  (2 * Math.atan(Math.exp(y / R)) - Math.PI / 2) * (180 / Math.PI);

/** Does `g` have its own land cell at this point? */
function hasCell(
  g: ClimateGrid,
  v: 'tmx' | 'tmn' | 'pre',
  month: number,
  lat: number,
  lon: number,
): boolean {
  const row = Math.round((g.lat0 - lat) / g.step);
  const col = Math.round((lon - g.lon0) / g.step);
  return !Number.isNaN(g.cell(v, month, row, col));
}

export interface Raster {
  url: string;
  bounds: [[number, number], [number, number]];
}

function frame(grid: ClimateGrid, pxPerDeg: number) {
  const [[south, west], [north, east]] = grid.bounds;
  const width = Math.round((east - west) * pxPerDeg);
  const yN = toY(north);
  const yS = toY(south);
  const height = Math.round(((yN - yS) / R) * (180 / Math.PI) * pxPerDeg);
  return { south, west, north, east, width, height, yN, yS };
}

/** Smooth temperature field, transparent over the sea. */
export function temperatureRaster(
  grid: ClimateGrid,
  month: number,
  metric: TempMetric,
  /** Grids drawn before this one: cells they cover are left to them. */
  earlier: ClimateGrid[] = [],
): Raster {
  const f = frame(grid, 12);
  const canvas = document.createElement('canvas');
  canvas.width = f.width;
  canvas.height = f.height;
  const ctx = canvas.getContext('2d')!;
  const img = ctx.createImageData(f.width, f.height);
  const v = metric === 'high' ? 'tmx' : 'tmn';
  for (let py = 0; py < f.height; py++) {
    const lat = toLat(f.yN - ((py + 0.5) / f.height) * (f.yN - f.yS));
    const fy = (grid.lat0 - lat) / grid.step;
    for (let px = 0; px < f.width; px++) {
      const lon = f.west + ((px + 0.5) / f.width) * (f.east - f.west);
      const fx = (lon - grid.lon0) / grid.step;
      // Inside a land cell only (no coastal extrapolation), bilinear between land cells.
      const own = grid.cell(v, month, Math.round(fy), Math.round(fx));
      if (Number.isNaN(own)) continue;
      if (earlier.some((g) => hasCell(g, v, month, lat, lon))) continue;
      const t = grid.sample(v, month, lat, lon);
      const [r, g, b] = tempRgb(t);
      const i = (py * f.width + px) * 4;
      img.data[i] = r;
      img.data[i + 1] = g;
      img.data[i + 2] = b;
      img.data[i + 3] = 215;
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

export interface RainDot {
  lat: number;
  lon: number;
  /** Radius in metres, so the dot keeps its size relative to the land at any zoom */
  radius: number;
}

/**
 * Rain as dots, one per grid cell: area proportional to monthly rainfall
 * (or to the number of rain days), so it reads on top of the temperatures.
 */
export function rainDots(
  grid: ClimateGrid,
  month: number,
  metric: RainMetric,
  threshold: number,
  /** Merge block × block cells into one dot (their average), for zoomed-out views */
  block = 1,
  /** Grids drawn before this one: their area is left to them. */
  earlier: ClimateGrid[] = [],
): RainDot[] {
  // A dot fills its block at 250 mm/month or 20 rainy days.
  const full = metric === 'mm' ? 250 : 20;
  const cellM = (grid.step * Math.PI * 6371000) / 180;
  const value = (row: number, col: number) =>
    metric === 'mm'
      ? grid.cell('pre', month, row, col)
      : grid.cellRainyDays(month, row, col, threshold);
  const dots: RainDot[] = [];
  // Blocks are aligned to the worldwide grid, not to this continent's corner,
  // so neighbouring continents merge cells into the same pattern of dots.
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
      if (val <= 0) continue;
      const lat = grid.lat0 - (r0 + (block - 1) / 2) * grid.step;
      const lonC = grid.lon0 + (c0 + (block - 1) / 2) * grid.step;
      if (earlier.some((g) => hasCell(g, 'pre', month, lat, lonC))) continue;
      const half =
        (cellM * block * Math.min(1, Math.cos((lat * Math.PI) / 180))) / 2;
      dots.push({
        lat,
        lon: lonC,
        radius: half * Math.sqrt(Math.min(1.3, val / full)) * 0.85,
      });
    }
  }
  return dots;
}
