import Service from '@ember/service';
import { cached, tracked } from '@glimmer/tracking';
import { TrackedMap, TrackedSet } from 'tracked-built-ins';
import ClimateGrid, {
  TiledClimate,
  tileArea,
  type ClimateHeader,
  type ClimateId,
} from 'forkcast/utils/climate';
import { fetchBuffer, fetchJson } from 'forkcast/utils/assets';
import type { CycleNetJson } from 'forkcast/utils/cyclenet';
import { errorMessage } from 'forkcast/utils/helpers';
import { DEFAULTS } from 'forkcast/utils/settings';
import { stored } from 'forkcast/utils/stored';
import {
  countriesFromTopology,
  type CountriesJson,
  type Topology,
} from 'forkcast/utils/topology';
import {
  routeFromJson,
  type Route,
  type RouteJson,
  type RouteMeta,
} from 'forkcast/utils/route';

export interface RouteOverview {
  id: string;
  color: string;
  lat: number[];
  lon: number[];
}

/** Town names of the world (data/forkcast_data/details.py). */
export interface PlacesJson {
  /** name, lon, lat, 1 for a capital, population, rank by size in its country (1 the biggest) */
  places: [string, number, number, number, number, number][];
}

/** Rivers (lines) and lakes (outer rings) of the world, as [lon, lat] points. */
export interface WaterJson {
  rivers: [number, number][][];
  lakes: [number, number][][];
}

/** The optional world files, fetched only when their layer is on. */
export interface DetailFiles {
  places: PlacesJson;
  water: WaterJson;
  /** The cycle network, for drawing routes that follow it */
  cyclenet: CycleNetJson;
}
export type DetailKind = keyof DetailFiles;

/** Tile ids kept in localStorage: a list of "<lat>_<lon>" strings. */
function parseTileIds(raw: unknown): string[] | undefined {
  return Array.isArray(raw) &&
    raw.every((id) => typeof id === 'string' && /^-?\d+_-?\d+$/.test(id))
    ? (raw as string[])
    : undefined;
}

/**
 * Loads the static data files built by the `data` container. The route list
 * and the country outlines load first, then the climate's header; a climate
 * tile (10° square) only when a route crosses it or the rider clicks it on
 * the map, and a route's track when it is picked. Nothing world-wide.
 * Switching the climate loads the same tiles of it.
 */
export default class AtlasService extends Service {
  /** The preset routes */
  @tracked presets: RouteMeta[] = [];
  /** Every preset route simplified to ~1 km, for drawing them all on the map */
  @tracked overview: RouteOverview[] = [];
  @tracked countries?: CountriesJson;
  /** The climate shown, once its header is in */
  @tracked current?: { header: ClimateHeader };
  @tracked climateId: ClimateId = DEFAULTS.climate;
  /** The current climate's tiles loaded so far, by id */
  tiles = new TrackedMap<string, ClimateGrid>();
  /** Tiles on their way, by id */
  loading = new TrackedSet<string>();
  /** The squares the rider clicked on the map, kept for the next visit */
  @stored('squares', parseTileIds) squares: string[] = [];
  @tracked error?: string;
  @tracked loadingRouteId?: string;
  tracks = new TrackedMap<string, Route>();
  /** Map details by kind, once fetched. */
  details = new TrackedMap<string, DetailFiles[DetailKind]>();

  #basics?: Promise<void>;
  #climateLoads = new Map<string, Promise<{ header: ClimateHeader }>>();
  /** By "<climate>/<tile id>" */
  #tileLoads = new Map<string, Promise<ClimateGrid>>();
  #routeLoads = new Map<string, Promise<Route>>();
  #detailLoads = new Map<string, Promise<void>>();
  /** The tiles each purpose wants (the route, the help's towns…), so a climate switch loads them again. */
  #wanted = new Map<string, string[]>();

  /** The climate, from the finest data loaded at each point. */
  @cached
  get climate(): TiledClimate | undefined {
    const c = this.current;
    return c ? new TiledClimate(c.header, new Map(this.tiles)) : undefined;
  }

  /** The route list, the routes' outlines and the countries: needed before anything else. */
  loadBasics(): Promise<void> {
    this.#basics ??= Promise.all([
      fetchJson<{ routes: RouteMeta[] }>('routes/index.json'),
      fetchJson<{ routes: RouteOverview[] }>('routes/overview.json'),
      fetchJson<Topology>('countries.json'),
    ]).then(
      ([index, overview, topo]) => {
        this.presets = index.routes;
        this.overview = overview.routes;
        this.countries = countriesFromTopology(topo);
      },
      (e: unknown) => {
        this.error = errorMessage(e);
      },
    );
    return this.#basics;
  }

  /**
   * A promise from `cache` under `key`, made by `make` the first time; a
   * failed one is forgotten, so asking again retries it.
   */
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

  #loadClimate(climate: ClimateId): Promise<{ header: ClimateHeader }> {
    return this.#once(this.#climateLoads, climate, async () => ({
      header: await fetchJson<ClimateHeader>(`climate/${climate}.json`),
    }));
  }

  /**
   * Show a climate: the basics, its header, then the tiles the route and the
   * clicked squares want, in it. Earlier tiles of another climate go.
   */
  async show(climate = this.climateId): Promise<void> {
    try {
      const [, loaded] = await Promise.all([
        this.loadBasics(),
        this.#loadClimate(climate),
      ]);
      if (climate !== this.climateId || !this.current) {
        this.climateId = climate;
        this.current = loaded;
        this.tiles.clear();
      }
      await this.#loadWanted();
    } catch (e) {
      this.error = errorMessage(e);
    }
  }

  /**
   * Load these tiles for `purpose` ("route": what the route crosses; "help":
   * the help's towns…), replacing what it wanted before.
   * Loaded tiles stay; ids without a tile (sea) are skipped.
   */
  want(purpose: string, ids: string[]): Promise<void> {
    this.#wanted.set(purpose, ids);
    return this.#loadWanted();
  }

  /** Load a square the rider clicked, and keep it for the next visit. */
  pick(id: string): Promise<void> {
    if (!this.squares.includes(id)) this.squares = [...this.squares, id];
    return this.#loadWanted();
  }

  async #loadWanted(): Promise<void> {
    // The trip asks for its tiles while it renders: mark them loading after it.
    await Promise.resolve();
    const c = this.current;
    if (!c) return;
    const climate = this.climateId;
    const exists = new Set(c.header.tiles);
    const ids = [
      ...new Set([...this.#wanted.values(), this.squares].flat()),
    ].filter((id) => exists.has(id) && !this.tiles.has(id));
    try {
      await Promise.all(
        ids.map((id) =>
          this.#once(this.#tileLoads, `${climate}/${id}`, () => {
            this.loading.add(id);
            return fetchBuffer(`climate/${climate}/${id}.bin`)
              .then((buffer) => tileGrid(c.header, id, buffer))
              .finally(() => this.loading.delete(id));
          }).then((grid) => {
            // A tile that arrives after a switch to another climate is dropped.
            if (this.climateId === climate) this.tiles.set(id, grid);
          }),
        ),
      );
    } catch (e) {
      this.error = errorMessage(e);
    }
  }

  /** A map detail, if fetched; undefined until then. */
  detail<K extends DetailKind>(kind: K): DetailFiles[K] | undefined {
    return this.details.get(kind) as DetailFiles[K] | undefined;
  }

  /**
   * Fetch a map detail, once. Called only while its layer is on, so a rider
   * who keeps Cities or Water off never downloads them.
   */
  loadDetail(kind: DetailKind): Promise<void> {
    return this.#once(this.#detailLoads, kind, () =>
      fetchJson<DetailFiles[DetailKind]>(`${kind}.json`).then((data) => {
        this.details.set(kind, data);
      }),
    ).catch((e: unknown) => {
      this.error = errorMessage(e);
    });
  }

  /** A preset route's track, once; undefined if it couldn't be loaded. */
  loadRoute(id: string): Promise<Route | undefined> {
    return this.#once(this.#routeLoads, id, () => this.#loadRoute(id)).catch(
      (e: unknown) => {
        this.error = errorMessage(e);
        return undefined;
      },
    );
  }

  async #loadRoute(id: string): Promise<Route> {
    this.loadingRouteId = id;
    try {
      const route = routeFromJson(
        await fetchJson<RouteJson>(`routes/${id}.json`),
      );
      this.tracks.set(id, route);
      return route;
    } finally {
      if (this.loadingRouteId === id) this.loadingRouteId = undefined;
    }
  }
}

/** A tile's grid: `size` × `size` cells from its south-west corner up to and including its far edges. */
function tileGrid(
  header: ClimateHeader,
  id: string,
  buffer: ArrayBuffer,
): ClimateGrid {
  const area = tileArea(id, header.tile);
  const [[, west], [north]] = area;
  return new ClimateGrid(
    header,
    {
      lon0: west,
      lat0: north,
      step: header.step,
      rows: header.size,
      cols: header.size,
    },
    buffer,
    area,
  );
}

declare module '@ember/service' {
  interface Registry {
    atlas: AtlasService;
  }
}
