// Route geometry: cumulative distances, positions along a route, GPX in/out.

export interface RoutePoint {
  lat: number;
  lon: number;
  ele: number | null;
  /** Cumulative riding distance from the start, km */
  km: number;
}

export interface Town {
  name: string;
  km: number;
  lat: number;
  lon: number;
}

export interface Route {
  id: string;
  name: string;
  /** Group in the route picker: "Demo", "EuroVelo" or "Yours" */
  group: string;
  color: string;
  /** Where the track comes from, for attribution */
  source?: string;
  /** Preset routes ship with the app and cannot be deleted. */
  isPreset: boolean;
  url?: string;
  points: RoutePoint[];
  towns: Town[];
  /** Total riding distance, km (ferry legs excluded) */
  km: number;
}

/** One entry of out/routes/index.json */
export interface RouteMeta {
  id: string;
  name: string;
  group: string;
  color: string;
  url: string;
  km: number;
}

/** out/routes/<id>.json */
export interface RouteJson extends RouteMeta {
  source: string;
  lat: number[];
  lon: number[];
  ele: (number | null)[];
  km_at: number[];
  ferry: number[];
  towns: Town[];
}

export function routeFromJson(r: RouteJson): Route {
  return {
    id: r.id,
    name: r.name,
    group: r.group,
    color: r.color,
    url: r.url || undefined,
    source: r.source,
    isPreset: true,
    km: r.km,
    towns: r.towns,
    points: r.lat.map((lat, i) => ({
      lat,
      lon: r.lon[i]!,
      ele: r.ele[i] ?? null,
      km: r.km_at[i]!,
    })),
  };
}

export function haversineKm(
  a: { lat: number; lon: number },
  b: { lat: number; lon: number },
): number {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 6371.0088 * 2 * Math.asin(Math.sqrt(h));
}

/** Build route points (with cumulative km) from plain coordinates. */
export function withDistances(
  coords: { lat: number; lon: number; ele?: number | null }[],
): RoutePoint[] {
  let km = 0;
  return coords.map((c, i) => {
    if (i > 0) km += haversineKm(coords[i - 1]!, c);
    return { lat: c.lat, lon: c.lon, ele: c.ele ?? null, km };
  });
}

/** Index of the last point at or before `km` (binary search). */
function indexAt(points: RoutePoint[], km: number): number {
  let lo = 0;
  let hi = points.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (points[mid]!.km <= km) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/** Interpolated position at a distance along the route. */
export function pointAt(points: RoutePoint[], km: number): RoutePoint {
  const last = points[points.length - 1]!;
  if (km <= 0) return points[0]!;
  if (km >= last.km) return last;
  const i = indexAt(points, km);
  const a = points[i]!;
  const b = points[Math.min(i + 1, points.length - 1)]!;
  const f = b.km > a.km ? (km - a.km) / (b.km - a.km) : 0;
  return {
    lat: a.lat + (b.lat - a.lat) * f,
    lon: a.lon + (b.lon - a.lon) * f,
    ele: a.ele !== null && b.ele !== null ? a.ele + (b.ele - a.ele) * f : a.ele,
    km,
  };
}

/** Points between two distances, inclusive of interpolated ends. */
export function slice(
  points: RoutePoint[],
  fromKm: number,
  toKm: number,
): RoutePoint[] {
  const out = [pointAt(points, fromKm)];
  for (const p of points) {
    if (p.km > fromKm && p.km < toKm) out.push(p);
  }
  out.push(pointAt(points, toKm));
  return out;
}

/** Total ascent between two distances, m. */
export function climbBetween(
  points: RoutePoint[],
  fromKm: number,
  toKm: number,
): number | null {
  const seg = slice(points, fromKm, toKm).filter((p) => p.ele !== null);
  if (seg.length < 2) return null;
  let up = 0;
  for (let i = 1; i < seg.length; i++) {
    const d = seg[i]!.ele! - seg[i - 1]!.ele!;
    if (d > 0) up += d;
  }
  return up;
}

/** Closest town at or before `km` (towns are only known for preset routes). */
export function townNear(route: Route, km: number): string | undefined {
  let best: Town | undefined;
  let bestD = Infinity;
  for (const t of route.towns) {
    const d = Math.abs(t.km - km);
    if (d < bestD) {
      bestD = d;
      best = t;
    }
  }
  return best && bestD < 40 ? best.name : undefined;
}

/** Same route walked backwards: distances measured from the other end. */
export function reversed(route: Route): Route {
  const total = route.points[route.points.length - 1]?.km ?? 0;
  return {
    ...route,
    points: [...route.points]
      .reverse()
      .map((p) => ({ ...p, km: total - p.km })),
    towns: [...route.towns].reverse().map((t) => ({ ...t, km: total - t.km })),
  };
}

export function parseGpx(
  xml: string,
): { lat: number; lon: number; ele: number | null }[] {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');
  if (doc.querySelector('parsererror')) {
    throw new Error('This file is not valid GPX.');
  }
  let nodes = Array.from(doc.getElementsByTagName('trkpt'));
  if (nodes.length === 0) nodes = Array.from(doc.getElementsByTagName('rtept'));
  if (nodes.length === 0) nodes = Array.from(doc.getElementsByTagName('wpt'));
  if (nodes.length < 2) {
    throw new Error('The GPX file has no track with at least two points.');
  }
  return nodes.map((n) => {
    const ele = n.getElementsByTagName('ele')[0]?.textContent;
    return {
      lat: Number(n.getAttribute('lat')),
      lon: Number(n.getAttribute('lon')),
      ele: ele ? Number(ele) : null,
    };
  });
}

export function gpxName(xml: string): string | undefined {
  const doc = new DOMParser().parseFromString(xml, 'application/xml');
  return (
    doc.querySelector('trk > name')?.textContent?.trim() ||
    doc.querySelector('metadata > name')?.textContent?.trim() ||
    undefined
  );
}

export function toGpx(route: Route): string {
  const esc = (s: string) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const pts = route.points
    .map(
      (p) =>
        `      <trkpt lat="${p.lat.toFixed(5)}" lon="${p.lon.toFixed(5)}">${
          p.ele === null ? '' : `<ele>${Math.round(p.ele)}</ele>`
        }</trkpt>`,
    )
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Wheelther" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>${esc(route.name)}</name>
    <trkseg>
${pts}
    </trkseg>
  </trk>
</gpx>
`;
}
