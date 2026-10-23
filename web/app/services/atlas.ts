import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { TrackedMap } from 'tracked-built-ins';
import ClimateGrid, { type ClimateGridJson } from 'wheelther/utils/climate';
import {
  routeFromJson,
  type Route,
  type RouteJson,
  type RouteMeta,
} from 'wheelther/utils/route';

export type CountriesJson = GeoJSON.FeatureCollection<GeoJSON.MultiPolygon>;

async function get<T>(name: string): Promise<T> {
  const res = await fetch(`${import.meta.env.BASE_URL}data/${name}`);
  if (!res.ok) {
    throw new Error(
      `Could not load data/${name} (HTTP ${res.status}). Build it with: docker compose --profile tools run --rm data`,
    );
  }
  return (await res.json()) as T;
}

/**
 * Loads the static data files built by the `data` container (public/data).
 * The route index loads up front; each route's track only when it is picked.
 */
export default class AtlasService extends Service {
  @tracked climate?: ClimateGrid;
  @tracked presets: RouteMeta[] = [];
  @tracked countries?: CountriesJson;
  @tracked error?: string;
  @tracked loadingRouteId?: string;
  tracks = new TrackedMap<string, Route>();

  #loading?: Promise<void>;
  #routeLoads = new Map<string, Promise<Route | undefined>>();

  load(): Promise<void> {
    this.#loading ??= this.#load();
    return this.#loading;
  }

  async #load(): Promise<void> {
    try {
      const [climate, index, countries] = await Promise.all([
        get<ClimateGridJson>('climate.json'),
        get<{ routes: RouteMeta[] }>('routes/index.json'),
        get<CountriesJson>('countries.json'),
      ]);
      this.climate = new ClimateGrid(climate);
      this.presets = index.routes;
      this.countries = countries;
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
    }
  }

  loadRoute(id: string): Promise<Route | undefined> {
    let p = this.#routeLoads.get(id);
    if (!p) {
      p = this.#loadRoute(id);
      this.#routeLoads.set(id, p);
    }
    return p;
  }

  async #loadRoute(id: string): Promise<Route | undefined> {
    if (!this.presets.some((r) => r.id === id)) return undefined;
    this.loadingRouteId = id;
    try {
      const route = routeFromJson(await get<RouteJson>(`routes/${id}.json`));
      this.tracks.set(id, route);
      return route;
    } catch (e) {
      this.#routeLoads.delete(id);
      this.error = e instanceof Error ? e.message : String(e);
      return undefined;
    } finally {
      if (this.loadingRouteId === id) this.loadingRouteId = undefined;
    }
  }
}

declare module '@ember/service' {
  interface Registry {
    atlas: AtlasService;
  }
}
