import Service from '@ember/service';
import { cached, tracked } from '@glimmer/tracking';
import { TrackedMap } from 'tracked-built-ins';
import ClimateGrid, {
  ClimateSet,
  type ClimateHeader,
} from 'forkcast/utils/climate';
import { fetchBuffer, fetchJson, hasAsset } from 'forkcast/utils/assets';
import type { CycleNetJson } from 'forkcast/utils/cyclenet';
import { errorMessage } from 'forkcast/utils/helpers';
import {
  routeFromJson,
  type Route,
  type RouteJson,
  type RouteMeta,
} from 'forkcast/utils/route';

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
export interface RouteOverview {
  id: string;
  continent: string;
  color: string;
  lat: number[];
  lon: number[];
}

/** City and mountain-range names of a continent (data/forkcast_data/details.py). */
export interface PlacesJson {
  /** name, lon, lat, 1 for a capital */
  places: [string, number, number, number][];
  /** name, lon, lat */
  ranges: [string, number, number][];
}

/** Rivers (lines) and lakes (outer rings) of a continent, as [lon, lat] points. */
export interface WaterJson {
  rivers: [number, number][][];
  lakes: [number, number][][];
}

/** The optional per-continent files, fetched only when their layer is on. */
export interface DetailFiles {
  places: PlacesJson;
  water: WaterJson;
  /** The cycle network, for drawing routes that follow it (not every continent has one) */
  cyclenet: CycleNetJson;
}
export type DetailKind = keyof DetailFiles;

export interface LoadedContinent {
  continent: Continent;
  climate: ClimateGrid;
  countries: CountriesJson;
}

export default class AtlasService extends Service {
  @tracked continents: Continent[] = [];
  /** One SVG path per continent id (plus "other"), for the map's continent shapes */
  @tracked world?: Record<string, string>;
  /** Every preset route simplified to ~1 km, for drawing them all on the map */
  @tracked overview: RouteOverview[] = [];
  /** The continents whose data is shown, in the order they were added. */
  @tracked loaded: LoadedContinent[] = [];
  @tracked error?: string;
  @tracked loadingRouteId?: string;
  @tracked loadingContinentIds: string[] = [];
  tracks = new TrackedMap<string, Route>();
  /** Map details by "<kind>/<continent id>", once fetched. */
  details = new TrackedMap<string, DetailFiles[DetailKind]>();

  #manifest?: Promise<void>;
  #continentLoads = new Map<string, Promise<LoadedContinent>>();
  #routeLoads = new Map<string, Promise<Route | undefined>>();
  #detailLoads = new Map<string, Promise<void>>();

  /** All loaded continents' climate as one (the first grid covering a point answers). */
  @cached
  get climate(): ClimateSet | undefined {
    return this.loaded.length
      ? new ClimateSet(this.loaded.map((l) => l.climate))
      : undefined;
  }

  get loadedIds(): string[] {
    return this.loaded.map((l) => l.continent.id);
  }

  /** Preset routes of every loaded continent. */
  get presets(): RouteMeta[] {
    return this.loaded.flatMap((l) => l.continent.routes);
  }

  loadManifest(): Promise<void> {
    this.#manifest ??= Promise.all([
      fetchJson<{ continents: Continent[] }>('manifest.json'),
      fetchJson<Record<string, string>>('world.json'),
      fetchJson<{ routes: RouteOverview[] }>('routes/overview.json'),
    ]).then(
      ([m, world, overview]) => {
        this.continents = m.continents;
        this.world = world;
        this.overview = overview.routes;
      },
      (e: unknown) => {
        this.error = errorMessage(e);
      },
    );
    return this.#manifest;
  }

  #fetchContinent(c: Continent): Promise<LoadedContinent> {
    let load = this.#continentLoads.get(c.id);
    if (!load) {
      load = Promise.all([
        fetchJson<ClimateHeader>(`${c.id}/climate.json`),
        fetchBuffer(`${c.id}/climate.bin`),
        fetchJson<CountriesJson>(`${c.id}/countries.json`),
      ]).then(([header, buffer, countries]) => ({
        continent: c,
        climate: new ClimateGrid(header, buffer),
        countries,
      }));
      load.catch(() => this.#continentLoads.delete(c.id));
      this.#continentLoads.set(c.id, load);
    }
    return load;
  }

  /**
   * Show exactly these continents (in this order), loading any not loaded yet.
   * Unknown ids are skipped; returns the ids actually shown.
   */
  async show(ids: string[]): Promise<string[]> {
    await this.loadManifest();
    const wanted = ids
      .map((id) => this.continents.find((c) => c.id === id))
      .filter((c): c is Continent => c !== undefined);
    this.loadingContinentIds = wanted
      .filter((c) => !this.loadedIds.includes(c.id))
      .map((c) => c.id);
    try {
      this.loaded = await Promise.all(
        wanted.map((c) => this.#fetchContinent(c)),
      );
    } catch (e) {
      this.error = errorMessage(e);
    } finally {
      this.loadingContinentIds = [];
    }
    return this.loadedIds;
  }

  /** A continent's map details, if fetched; undefined until then. */
  detail<K extends DetailKind>(
    kind: K,
    continentId: string,
  ): DetailFiles[K] | undefined {
    return this.details.get(`${kind}/${continentId}`) as
      DetailFiles[K] | undefined;
  }

  /**
   * Fetch a continent's map details, once. Called only while their layer is
   * on, so a rider who keeps Cities or Water off never downloads them.
   */
  loadDetail(kind: DetailKind, continentId: string): Promise<void> {
    const key = `${kind}/${continentId}`;
    let load = this.#detailLoads.get(key);
    if (!load && !hasAsset(`${continentId}/${kind}.json`)) {
      load = Promise.resolve();
      this.#detailLoads.set(key, load);
    }
    if (!load) {
      load = fetchJson<DetailFiles[DetailKind]>(
        `${continentId}/${kind}.json`,
      ).then(
        (data) => {
          this.details.set(key, data);
        },
        (e: unknown) => {
          this.#detailLoads.delete(key);
          this.error = errorMessage(e);
        },
      );
      this.#detailLoads.set(key, load);
    }
    return load;
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
      this.error = errorMessage(e);
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
