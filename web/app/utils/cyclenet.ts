// The cycle network (data/forkcast_data/cyclenet.py) as a graph, for drawing
// routes that follow it: snap a click to the nearest route, then find the
// shortest way along the routes from the previous point.
//
// Every point of a line is a node, and lines that share a point (coordinates
// are rounded to 0.001°, so a junction is the same point in both) are joined
// there. Distances are great-circle km.

import { km, lineKm } from './geo';

export interface CycleNetJson {
  /** Lines of [lon, lat] points */
  lines: [number, number][][];
}

export interface LatLon {
  lat: number;
  lon: number;
}

const RAD = Math.PI / 180;

/** Grid cell size for the nearest-segment lookup, degrees. */
const CELL = 0.05;
/** Dead ends of the network are linked to another route this close, km. */
const BRIDGE_KM = 1;

/** A min-heap of [cost, node], for the shortest-path search. */
class Heap {
  items: [number, number][] = [];
  get size() {
    return this.items.length;
  }
  push(item: [number, number]) {
    const a = this.items;
    a.push(item);
    let i = a.length - 1;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (a[p]![0] <= a[i]![0]) break;
      [a[p], a[i]] = [a[i]!, a[p]!];
      i = p;
    }
  }
  pop(): [number, number] {
    const a = this.items;
    const top = a[0]!;
    const last = a.pop()!;
    if (a.length) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1;
        const r = l + 1;
        let m = i;
        if (l < a.length && a[l]![0] < a[m]![0]) m = l;
        if (r < a.length && a[r]![0] < a[m]![0]) m = r;
        if (m === i) break;
        [a[m], a[i]] = [a[i]!, a[m]!];
        i = m;
      }
    }
    return top;
  }
}

/** A point snapped onto the network: on the segment from node `a` to node `b`. */
export interface Snap {
  point: LatLon;
  a: number;
  b: number;
  /** km from the point to `a` and to `b` along the segment */
  toA: number;
  toB: number;
  /** km from the original point to the network */
  away: number;
}

export class CycleNet {
  lat: number[] = [];
  lon: number[] = [];
  /** Neighbours of each node, with the distance to them in km */
  edges: [number, number][][] = [];
  /** Every segment once, as node pairs */
  #segments: [number, number][] = [];
  #ids = new Map<string, number>();
  /** Segments by grid cell (a segment is in every cell its box touches) */
  #grid = new Map<string, number[]>();

  constructor(files: CycleNetJson[]) {
    for (const file of files) {
      for (const line of file.lines) {
        let prev = -1;
        for (const [lon, lat] of line) {
          const node = this.#node(lat, lon);
          if (prev >= 0 && prev !== node) this.#segment(prev, node);
          prev = node;
        }
      }
    }
    this.#bridgeDeadEnds();
  }

  /**
   * Link every dead end to the nearest other route within BRIDGE_KM: OSM maps
   * routes in sections that often stop just short of the next one (at
   * borders) or meet it part-way along, which would leave the network in
   * pieces. A link to the middle of a segment splits it there.
   */
  #bridgeDeadEnds(): void {
    const count = this.size;
    for (let id = 0; id < count; id++) {
      const edges = this.edges[id]!;
      if (edges.length !== 1) continue;
      const own = new Set([id, edges[0]![0]]);
      const s = this.snap(this.point(id), BRIDGE_KM, own);
      if (!s) continue;
      let to: number;
      if (s.toA < 0.01) to = s.a;
      else if (s.toB < 0.01) to = s.b;
      else {
        to = this.#node(s.point.lat, s.point.lon);
        this.#segment(s.a, to);
        this.#segment(to, s.b);
      }
      if (to !== id) this.#segment(id, to);
    }
  }

  get size(): number {
    return this.lat.length;
  }

  #node(lat: number, lon: number): number {
    const key = `${lat},${lon}`;
    let id = this.#ids.get(key);
    if (id === undefined) {
      id = this.lat.length;
      this.lat.push(lat);
      this.lon.push(lon);
      this.edges.push([]);
      this.#ids.set(key, id);
    }
    return id;
  }

  #segment(a: number, b: number): void {
    const d = km(this.lat[a]!, this.lon[a]!, this.lat[b]!, this.lon[b]!);
    this.edges[a]!.push([b, d]);
    this.edges[b]!.push([a, d]);
    const id = this.#segments.push([a, b]) - 1;
    const r0 = Math.floor(Math.min(this.lat[a]!, this.lat[b]!) / CELL);
    const r1 = Math.floor(Math.max(this.lat[a]!, this.lat[b]!) / CELL);
    const c0 = Math.floor(Math.min(this.lon[a]!, this.lon[b]!) / CELL);
    const c1 = Math.floor(Math.max(this.lon[a]!, this.lon[b]!) / CELL);
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const key = `${r},${c}`;
        const list = this.#grid.get(key);
        if (list) list.push(id);
        else this.#grid.set(key, [id]);
      }
    }
  }

  point(id: number): LatLon {
    return { lat: this.lat[id]!, lon: this.lon[id]! };
  }

  /** The nearest point on the network, if one is within `maxKm`, leaving
   * out segments that touch the `skip` nodes. */
  snap(p: LatLon, maxKm: number, skip?: Set<number>): Snap | undefined {
    // Flat x/y in km around the point: exact enough over a few km.
    const kx = 111.32 * Math.cos(p.lat * RAD);
    const ky = 110.57;
    const span = Math.ceil(maxKm / (CELL * Math.min(kx, ky)));
    const r0 = Math.floor(p.lat / CELL);
    const c0 = Math.floor(p.lon / CELL);
    const seen = new Set<number>();
    let best: Snap | undefined;
    for (let r = r0 - span; r <= r0 + span; r++) {
      for (let c = c0 - span; c <= c0 + span; c++) {
        for (const id of this.#grid.get(`${r},${c}`) ?? []) {
          if (seen.has(id)) continue;
          seen.add(id);
          const [a, b] = this.#segments[id]!;
          if (skip && (skip.has(a) || skip.has(b))) continue;
          const ax = (this.lon[a]! - p.lon) * kx;
          const ay = (this.lat[a]! - p.lat) * ky;
          const bx = (this.lon[b]! - p.lon) * kx;
          const by = (this.lat[b]! - p.lat) * ky;
          const dx = bx - ax;
          const dy = by - ay;
          const len2 = dx * dx + dy * dy;
          const t = len2
            ? Math.min(1, Math.max(0, -(ax * dx + ay * dy) / len2))
            : 0;
          const away = Math.hypot(ax + t * dx, ay + t * dy);
          if (away > maxKm || (best && away >= best.away)) continue;
          const len = Math.sqrt(len2);
          best = {
            point: {
              lat: this.lat[a]! + t * (this.lat[b]! - this.lat[a]!),
              lon: this.lon[a]! + t * (this.lon[b]! - this.lon[a]!),
            },
            a,
            b,
            toA: t * len,
            toB: (1 - t) * len,
            away,
          };
        }
      }
    }
    return best;
  }

  /**
   * The shortest way along the network between two snapped points (A* on
   * distance), from one to the other inclusive, or undefined if they aren't
   * connected.
   */
  route(from: Snap, to: Snap): LatLon[] | undefined {
    const sameSegment =
      (from.a === to.a && from.b === to.b) ||
      (from.a === to.b && from.b === to.a);
    if (sameSegment) return [from.point, to.point];
    const goal = (id: number) =>
      km(this.lat[id]!, this.lon[id]!, to.point.lat, to.point.lon);
    const finish = new Map([
      [to.a, to.toA],
      [to.b, to.toB],
    ]);
    const cost = new Map<number, number>();
    const came = new Map<number, number>();
    const open = new Heap();
    for (const [id, c] of [
      [from.a, from.toA],
      [from.b, from.toB],
    ] as const) {
      if (c < (cost.get(id) ?? Infinity)) {
        cost.set(id, c);
        open.push([c + goal(id), id]);
      }
    }
    let best = Infinity;
    let end = -1;
    while (open.size) {
      const [estimate, id] = open.pop();
      if (estimate >= best) break;
      const here = cost.get(id)!;
      const last = finish.get(id);
      if (last !== undefined && here + last < best) {
        best = here + last;
        end = id;
      }
      for (const [next, d] of this.edges[id]!) {
        const c = here + d;
        if (c < (cost.get(next) ?? Infinity)) {
          cost.set(next, c);
          came.set(next, id);
          open.push([c + goal(next), next]);
        }
      }
    }
    if (end < 0) return undefined;
    const nodes = [this.point(end)];
    for (let n = end; came.has(n);) {
      n = came.get(n)!;
      nodes.push(this.point(n));
    }
    return [from.point, ...nodes.reverse(), to.point];
  }

  /**
   * The network line for a sketch of clicks: each click moves onto the
   * nearest network line within `clickKm`, and consecutive clicks are joined
   * by the shortest way along the network. A click with no line near stays
   * where it is, and a join that isn't connected or would be a detour (longer
   * than `detour` times the straight distance, plus a few km) is a straight
   * line.
   */
  match(sketch: LatLon[], clickKm: number, detour = 3): LatLon[] {
    const out: LatLon[] = [];
    const add = (p: LatLon) => {
      const last = out[out.length - 1];
      if (!last || last.lat !== p.lat || last.lon !== p.lon) out.push(p);
    };
    let prev: Snap | undefined;
    for (const click of sketch) {
      const here = this.snap(click, clickKm);
      if (!here) {
        add(click);
        prev = undefined;
        continue;
      }
      if (prev) {
        const path = this.route(prev, here);
        const straight = km(
          prev.point.lat,
          prev.point.lon,
          here.point.lat,
          here.point.lon,
        );
        if (path && lineKm(path) <= detour * straight + 3) path.forEach(add);
        else add(here.point);
      } else {
        add(here.point);
      }
      prev = here;
    }
    return out;
  }
}
