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
import { DEFAULTS } from 'forkcast/utils/settings';
import type { ClimateId } from 'forkcast/services/planner';
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

export interface RouteOverview {
  id: string;
  continent: string;
  color: string;
  lat: number[];
  lon: number[];
}

/** City names of a continent (data/forkcast_data/details.py). */
export interface PlacesJson {
  /** name, lon, lat, 1 for a capital, population, rank by size in its country (1 the biggest) */
  places: [string, number, number, number, number, number][];
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

/** A continent's grid file of a climate, without its extension. */
function gridFile(continentId: string, climate: ClimateId): string {
  return climate === 'last15'
    ? `${continentId}/climate`
    : `${continentId}/climate-${climate}`;
}

/**
 * Loads the static data files built by the `data` container. The manifest is
 * small and loads first; a continent's climate grid and borders load when it
 * is opened, and a route's track when it is picked. Switching the climate
 * loads the other grids of the continents shown; borders are kept.
 */
export default class AtlasService extends Service {
  @tracked continents: Continent[] = [];
  /** One SVG path per continent id (plus "other"), for the map's continent shapes */
  @tracked world?: Record<string, string>;
  /** Every preset route simplified to ~1 km, for drawing them all on the map */
  @tracked overview: RouteOverview[] = [];
  /** The continents whose data is shown, in the order they were added. */
  @tracked loaded: LoadedContinent[] = [];
  /** The climate of the grids in `loaded`. */
  @tracked climateId: ClimateId = DEFAULTS.climate;
  @tracked error?: string;
  @tracked loadingRouteId?: string;
  @tracked loadingContinentIds: string[] = [];
  tracks = new TrackedMap<string, Route>();
  /** Map details by "<kind>/<continent id>", once fetched. */
  details = new TrackedMap<string, DetailFiles[DetailKind]>();

  #manifest?: Promise<void>;
  /** By "<climate>/<continent id>" */
  #gridLoads = new Map<string, Promise<ClimateGrid>>();
  #countryLoads = new Map<string, Promise<CountriesJson>>();
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

  /** A promise from `cache` under `key`, made by `make` once; forgotten if it fails, so it can be retried. */
  #once<T>(
    cache: Map<string, Promise<T>>,
    key: string,
    make: () => Promise<T>,
  ) {
    let load = cache.get(key);
    if (!load) {
      load = make();
      load.catch(() => cache.delete(key));
      cache.set(key, load);
    }
    return load;
  }

  async #fetchContinent(
    c: Continent,
    climate: ClimateId,
  ): Promise<LoadedContinent> {
    const file = gridFile(c.id, climate);
    const [grid, countries] = await Promise.all([
      this.#once(this.#gridLoads, `${climate}/${c.id}`, () =>
        Promise.all([
          fetchJson<ClimateHeader>(`${file}.json`),
          fetchBuffer(`${file}.bin`),
        ]).then(([header, buffer]) => new ClimateGrid(header, buffer)),
      ),
      this.#once(this.#countryLoads, c.id, () =>
        fetchJson<CountriesJson>(`${c.id}/countries.json`),
      ),
    ]);
    return { continent: c, climate: grid, countries };
  }

  /**
   * Show exactly these continents (in this order) in a climate (the one shown
   * by default), loading what isn't loaded yet. Unknown ids are skipped;
   * returns the ids actually shown.
   */
  async show(ids: string[], climate = this.climateId): Promise<string[]> {
    await this.loadManifest();
    const wanted = ids
      .map((id) => this.continents.find((c) => c.id === id))
      .filter((c): c is Continent => c !== undefined);
    this.loadingContinentIds = wanted
      .filter(
        (c) => climate !== this.climateId || !this.loadedIds.includes(c.id),
      )
      .map((c) => c.id);
    try {
      this.loaded = await Promise.all(
        wanted.map((c) => this.#fetchContinent(c, climate)),
      );
      this.climateId = climate;
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
