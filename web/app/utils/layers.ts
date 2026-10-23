// Renders the climate grid into Web-Mercator canvases for Leaflet image overlays.
// The grid is regular in latitude, the map is not, so every output row is
// re-projected rather than stretching the grid image.

import type ClimateGrid from './climate';
import { tempRgb } from './climate';
import type { RainMetric, TempMetric } from 'wheelther/services/planner';

const R = 6378137;
const toY = (lat: number) =>
  R * Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
const toLat = (y: number) =>
  (2 * Math.atan(Math.exp(y / R)) - Math.PI / 2) * (180 / Math.PI);

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
): RainDot[] {
  // A dot fills its cell at 250 mm/month or 20 rainy days.
  const full = metric === 'mm' ? 250 : 20;
  const cellM = (grid.step * Math.PI * 6371000) / 180;
  const dots: RainDot[] = [];
  for (let row = 0; row < grid.rows; row++) {
    const lat = grid.lat0 - row * grid.step;
    const half = (cellM * Math.min(1, Math.cos((lat * Math.PI) / 180))) / 2;
    for (let col = 0; col < grid.cols; col++) {
      const val =
        metric === 'mm'
          ? grid.cell('pre', month, row, col)
          : grid.cellRainyDays(month, row, col, threshold);
      if (Number.isNaN(val) || val <= 0) continue;
      dots.push({
        lat,
        lon: grid.lon0 + col * grid.step,
        radius: half * Math.sqrt(Math.min(1.3, val / full)) * 0.85,
      });
    }
  }
  return dots;
}
