import Service from '@ember/service';
import { encodeTrack } from 'forkcast/utils/route';
import { storage, stored } from 'forkcast/utils/stored';

/** A route you drew or imported, as saved in this browser. */
export interface SavedRoute {
  /** A random UUID: what links use to point at it */
  id: string;
  name: string;
  /** The whole track, encoded (see encodeTrack) */
  track: string;
  /** A drawn route's clicks and whether it followed the cycle routes, so it
   * can be drawn further; imported routes have none. */
  sketch?: { lat: number; lon: number }[];
  snap?: boolean;
}

type Coords = { lat: number; lon: number; ele?: number | null }[];

/** Ids of your own routes are UUIDs; preset ids are short names. */
/** Saved routes as read back from storage, leaving out any that aren't. */
function parseRoutes(raw: unknown): SavedRoute[] | undefined {
  if (!Array.isArray(raw)) return undefined;
  return raw.filter((r: unknown): r is SavedRoute => {
    const o = r as Partial<Record<keyof SavedRoute, unknown>> | null;
    return (
      typeof o?.id === 'string' &&
      typeof o.name === 'string' &&
      typeof o.track === 'string'
    );
  });
}

export const isOwnRouteId = (id: string): boolean =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id);

/**
 * Your own routes, kept in this browser's storage and nowhere else: links to
 * them carry only the id, so they open only where the route was made.
 */
export default class MyRoutesService extends Service {
  @stored('routes', parseRoutes) routes: SavedRoute[] = [];

  /** Set when the browser refused to save (storage full or switched off). */
  get saveError(): string | undefined {
    return storage.failed
      ? "Your browser didn't let Forkcast save your routes (storage full or switched off), so they'll be gone when you close the page."
      : undefined;
  }

  find(id: string): SavedRoute | undefined {
    return this.routes.find((r) => r.id === id);
  }

  /** Save a new route; a track already saved is reused rather than doubled. */
  add(
    coords: Coords,
    name: string,
    drawing?: { sketch: SavedRoute['sketch']; snap: boolean },
  ): SavedRoute {
    const track = encodeTrack(coords);
    const same = this.routes.find((r) => r.track === track);
    if (same) return same;
    const route: SavedRoute = {
      id: crypto.randomUUID(),
      name: name.trim() || this.nextName(),
      track,
      ...(drawing && { sketch: drawing.sketch, snap: drawing.snap }),
    };
    this.routes = [...this.routes, route];
    return route;
  }

  /** A name for a new drawn route: "Route 1", "Route 2", … */
  nextName(): string {
    const taken = new Set(this.routes.map((r) => r.name));
    let n = this.routes.length + 1;
    while (taken.has(`Route ${n}`)) n++;
    return `Route ${n}`;
  }

  rename(id: string, name: string): void {
    this.#change(id, { name });
  }

  /** Replace a drawn route's shape (after drawing it further). */
  redraw(
    id: string,
    coords: Coords,
    sketch: SavedRoute['sketch'],
    snap: boolean,
  ): void {
    this.#change(id, { track: encodeTrack(coords), sketch, snap });
  }

  remove(id: string): void {
    this.routes = this.routes.filter((r) => r.id !== id);
  }

  #change(id: string, changes: Partial<SavedRoute>): void {
    this.routes = this.routes.map((r) =>
      r.id === id ? { ...r, ...changes } : r,
    );
  }
}

declare module '@ember/service' {
  interface Registry {
    'my-routes': MyRoutesService;
  }
}
