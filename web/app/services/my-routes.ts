import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { TrackedArray } from 'tracked-built-ins';
import { encodeTrack } from 'forkcast/utils/route';

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
export const isOwnRouteId = (id: string): boolean =>
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id);

/**
 * Your own routes, kept in this browser's storage and nowhere else: links to
 * them carry only the id, so they open only where the route was made.
 */
export default class MyRoutesService extends Service {
  /** The localStorage key (tests use their own). */
  get storageKey(): string {
    return 'forkcast:routes';
  }

  routes = new TrackedArray<SavedRoute>(this.#load());
  /** Set when the browser refused to save (storage full or switched off). */
  @tracked saveError?: string;

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
    this.routes.push(route);
    this.#save();
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
    const i = this.routes.findIndex((r) => r.id === id);
    if (i < 0) return;
    this.routes.splice(i, 1);
    this.#save();
  }

  #change(id: string, changes: Partial<SavedRoute>): void {
    const i = this.routes.findIndex((r) => r.id === id);
    if (i < 0) return;
    this.routes[i] = { ...this.routes[i]!, ...changes };
    this.#save();
  }

  #load(): SavedRoute[] {
    try {
      const raw: unknown = JSON.parse(
        localStorage.getItem(this.storageKey) ?? '[]',
      );
      return Array.isArray(raw)
        ? raw.filter((r: unknown): r is SavedRoute => {
            const o = r as Partial<Record<keyof SavedRoute, unknown>> | null;
            return (
              typeof o?.id === 'string' &&
              typeof o.name === 'string' &&
              typeof o.track === 'string'
            );
          })
        : [];
    } catch {
      return [];
    }
  }

  #save(): void {
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(this.routes));
      this.saveError = undefined;
    } catch {
      this.saveError =
        "Your browser didn't let Forkcast save your routes (storage full or switched off), so they'll be gone when you close the page.";
    }
  }
}

declare module '@ember/service' {
  interface Registry {
    'my-routes': MyRoutesService;
  }
}
