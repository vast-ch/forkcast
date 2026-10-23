import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { TrackedMap } from 'tracked-built-ins';
import ClimateGrid, { type ClimateHeader } from 'wheelther/utils/climate';
import { fetchBuffer, fetchJson } from 'wheelther/utils/assets';
import {
  routeFromJson,
  type Route,
  type RouteJson,
  type RouteMeta,
} from 'wheelther/utils/route';

export type CountriesJson = GeoJSON.FeatureCollection<GeoJSON.MultiPolygon>;

export interface Continent {
  id: string;
  name: string;
  /** lon_min, lat_min, lon_max, lat_max */
  bbox: [number, number, number, number];
  /** Size of its climate grid and borders, before compression */
  bytes: number;
  /** The same, gzipped: roughly what is downloaded */
  gzipBytes: number;
  routes: RouteMeta[];
}

/**
 * Loads the static data files built by the `data` container. The manifest is
 * small and loads first; a continent's climate grid and borders load when it
 * is opened, and a route's track when it is picked.
 */
export default class AtlasService extends Service {
  @tracked continents: Continent[] = [];
  /** One SVG path per continent id (plus "other"), for the picker map */
  @tracked world?: Record<string, string>;
  @tracked continent?: Continent;
  @tracked climate?: ClimateGrid;
  @tracked countries?: CountriesJson;
  @tracked error?: string;
  @tracked loadingRouteId?: string;
  tracks = new TrackedMap<string, Route>();

  #manifest?: Promise<void>;
  #continentLoads = new Map<
    string,
    Promise<{ climate: ClimateGrid; countries: CountriesJson }>
  >();
  #routeLoads = new Map<string, Promise<Route | undefined>>();

  get presets(): RouteMeta[] {
    return this.continent?.routes ?? [];
  }

  loadManifest(): Promise<void> {
    this.#manifest ??= Promise.all([
      fetchJson<{ continents: Continent[] }>('manifest.json'),
      fetchJson<Record<string, string>>('world.json'),
    ]).then(
      ([m, world]) => {
        this.continents = m.continents;
        this.world = world;
      },
      (e: unknown) => {
        this.error = e instanceof Error ? e.message : String(e);
      },
    );
    return this.#manifest;
  }

  /** Open a continent: loads its climate grid and borders (once per session). */
  async openContinent(id: string): Promise<Continent | undefined> {
    await this.loadManifest();
    const c = this.continents.find((x) => x.id === id);
    if (!c) return undefined;
    let load = this.#continentLoads.get(id);
    if (!load) {
      load = Promise.all([
        fetchJson<ClimateHeader>(`${id}/climate.json`),
        fetchBuffer(`${id}/climate.bin`),
        fetchJson<CountriesJson>(`${id}/countries.json`),
      ]).then(([header, buffer, countries]) => ({
        climate: new ClimateGrid(header, buffer),
        countries,
      }));
      this.#continentLoads.set(id, load);
    }
    try {
      const { climate, countries } = await load;
      this.continent = c;
      this.climate = climate;
      this.countries = countries;
      return c;
    } catch (e) {
      this.#continentLoads.delete(id);
      this.error = e instanceof Error ? e.message : String(e);
      return undefined;
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
    this.loadingRouteId = id;
    try {
      const route = routeFromJson(
        await fetchJson<RouteJson>(`routes/${id}.json`),
      );
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
