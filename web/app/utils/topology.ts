// The world's country outlines come as TopoJSON (data/forkcast_data/basemap.py):
// each border once, as quantized arcs that the countries' rings are made of.
// This turns them back into polygons, as basemap.countries() does.

/** The parts of a TopoJSON topology the outlines use. */
export interface Topology {
  transform: { scale: [number, number]; translate: [number, number] };
  /** Each arc's points, the first absolute, the rest as steps from the one before, quantized */
  arcs: [number, number][][];
  objects: {
    countries: {
      geometries: (
        | { type: 'Polygon'; arcs: number[][] }
        | { type: 'MultiPolygon'; arcs: number[][][] }
      )[];
    };
  };
}

export type CountriesJson = GeoJSON.FeatureCollection<GeoJSON.MultiPolygon>;

/**
 * Keep a ring that crosses the 180° meridian (Russia, Fiji, the Aleutians)
 * whole, on the side where most of its points are, so its fill isn't drawn
 * the long way round.
 */
function unwrap(ring: [number, number][]): [number, number][] {
  let min = Infinity;
  let max = -Infinity;
  let east = 0;
  for (const [x] of ring) {
    min = Math.min(min, x);
    max = Math.max(max, x);
    if (x > 0) east++;
  }
  if (max - min <= 180) return ring;
  const isEast = east >= ring.length / 2;
  return ring.map(([x, y]) => [
    isEast && x < 0 ? x + 360 : !isEast && x > 0 ? x - 360 : x,
    y,
  ]);
}

/** Every country as a GeoJSON MultiPolygon of [lon, lat] rings. */
export function countriesFromTopology(topo: Topology): CountriesJson {
  const [sx, sy] = topo.transform.scale;
  const [tx, ty] = topo.transform.translate;
  const arcs = topo.arcs.map((arc) => {
    let x = 0;
    let y = 0;
    return arc.map(([dx, dy]): [number, number] => {
      x += dx;
      y += dy;
      return [x * sx + tx, y * sy + ty];
    });
  });
  // A negative index is the arc ~i, walked backwards; joined arcs share their end point.
  const ring = (ids: number[]) => {
    const pts: [number, number][] = [];
    for (const i of ids) {
      const arc = i >= 0 ? arcs[i]! : [...arcs[~i]!].reverse();
      pts.push(...(pts.length ? arc.slice(1) : arc));
    }
    return unwrap(pts);
  };
  return {
    type: 'FeatureCollection',
    features: topo.objects.countries.geometries.map((g) => ({
      type: 'Feature',
      properties: {},
      geometry: {
        type: 'MultiPolygon',
        coordinates: (g.type === 'Polygon' ? [g.arcs] : g.arcs).map((poly) =>
          poly.map(ring),
        ),
      },
    })),
  };
}
