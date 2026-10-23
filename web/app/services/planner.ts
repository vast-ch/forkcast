import Service, { service } from '@ember/service';
import type Owner from '@ember/owner';
import { cached, tracked } from '@glimmer/tracking';
import { TrackedArray } from 'tracked-built-ins';
import type AtlasService from './atlas';
import type { DayClimate, RainThreshold } from 'wheelther/utils/climate';
import { planTrip, type Trip, type TripDay } from 'wheelther/utils/itinerary';
import {
  reversed,
  withDistances,
  type Route,
  type RoutePoint,
} from 'wheelther/utils/route';

export type TempMetric = 'high' | 'low';
export type RainMetric = 'mm' | 'days';

const STORAGE_KEY = 'wheelther:v3';
const CUSTOM_COLORS = ['#0f7b8a', '#b5179e', '#2a9d3f', '#c2410c', '#1d4ed8'];

interface Stored {
  month?: number;
  showTemp?: boolean;
  showRain?: boolean;
  tempMetric?: TempMetric;
  rainMetric?: RainMetric;
  rainThreshold?: RainThreshold;
  routeId?: string;
  start?: string;
  kmPerDay?: number;
  rideDays?: number;
  restDays?: number;
  isReversed?: boolean;
  custom?: {
    id: string;
    name: string;
    color: string;
    coords: [number, number, number | null][];
  }[];
}

/** What is under the mouse pointer on the map. */
export interface Hover {
  lat: number;
  lon: number;
  month: DayClimate | null;
  /** Set when the pointer is near the selected route */
  onRoute?: {
    km: number;
    day?: TripDay;
    weather?: DayClimate;
    point: RoutePoint;
  };
}

function load(): Stored {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}') as Stored;
  } catch {
    return {};
  }
}

/** The coming 1 January (today, if it is 1 January). */
function nextJanuary(): string {
  const now = new Date();
  const isNewYearsDay = now.getMonth() === 0 && now.getDate() === 1;
  return `${isNewYearsDay ? now.getFullYear() : now.getFullYear() + 1}-01-01`;
}

export default class PlannerService extends Service {
  @service declare atlas: AtlasService;

  // Map layers
  @tracked month: number;
  @tracked showTemp: boolean;
  @tracked showRain: boolean;
  @tracked tempMetric: TempMetric;
  @tracked rainMetric: RainMetric;
  /** mm of rain from which a day counts as rainy */
  @tracked rainThreshold: RainThreshold;

  // Trip
  @tracked routeId: string;
  @tracked start: string;
  @tracked kmPerDay: number;
  @tracked rideDays: number;
  @tracked restDays: number;
  @tracked isReversed: boolean;
  custom: TrackedArray<Route>;

  // Interaction
  @tracked hover?: Hover;
  @tracked highlightedDay?: number;
  @tracked isDrawing = false;
  drawn = new TrackedArray<{ lat: number; lon: number }>();

  constructor(owner: Owner) {
    super(owner);
    const s = load();
    this.month = s.month ?? 0;
    this.showTemp = s.showTemp ?? true;
    this.showRain = s.showRain ?? true;
    this.tempMetric = s.tempMetric ?? 'high';
    this.rainMetric = s.rainMetric ?? 'mm';
    this.rainThreshold = s.rainThreshold ?? 5;
    this.routeId = s.routeId ?? 'interlaken-malaga';
    this.start = s.start ?? nextJanuary();
    this.kmPerDay = s.kmPerDay ?? 80;
    this.rideDays = s.rideDays ?? 5;
    this.restDays = s.restDays ?? 1;
    this.isReversed = s.isReversed ?? false;
    this.custom = new TrackedArray(
      (s.custom ?? [])
        .map((r) => ({
          id: r.id,
          name: r.name,
          color: r.color,
          group: 'Yours',
          isPreset: false,
          towns: [],
          points: withDistances(
            r.coords.map(([lat, lon, ele]) => ({ lat, lon, ele })),
          ),
          km: 0,
        }))
        .map((r) => ({ ...r, km: r.points[r.points.length - 1]?.km ?? 0 })),
    );
  }

  save(): void {
    const s: Stored = {
      month: this.month,
      showTemp: this.showTemp,
      showRain: this.showRain,
      tempMetric: this.tempMetric,
      rainMetric: this.rainMetric,
      rainThreshold: this.rainThreshold,
      routeId: this.routeId,
      start: this.start,
      kmPerDay: this.kmPerDay,
      rideDays: this.rideDays,
      restDays: this.restDays,
      isReversed: this.isReversed,
      custom: this.custom.map((r) => ({
        id: r.id,
        name: r.name,
        color: r.color,
        coords: r.points.map((p) => [
          Math.round(p.lat * 1e5) / 1e5,
          Math.round(p.lon * 1e5) / 1e5,
          p.ele === null ? null : Math.round(p.ele),
        ]),
      })),
    };
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    } catch {
      // Storage can be unavailable (private window); settings just won't persist.
    }
  }

  set<K extends keyof this>(key: K, value: this[K]): void {
    this[key] = value;
    this.save();
  }

  /** Everything the route picker offers: preset metadata plus your own routes. */
  @cached
  get choices(): {
    id: string;
    name: string;
    group: string;
    km: number;
    color: string;
  }[] {
    return [...this.atlas.presets, ...this.custom];
  }

  /** The selected route as stored (always in its original direction), once its track is loaded. */
  @cached
  get baseRoute(): Route | undefined {
    return (
      this.custom.find((r) => r.id === this.routeId) ??
      this.atlas.tracks.get(this.routeId)
    );
  }

  /** Select a route, loading its track if it is a preset. */
  async selectRoute(id: string): Promise<void> {
    const known = this.choices.some((r) => r.id === id);
    this.routeId = known ? id : (this.atlas.presets[0]?.id ?? '');
    this.highlightedDay = undefined;
    this.save();
    if (!this.custom.some((r) => r.id === this.routeId)) {
      await this.atlas.loadRoute(this.routeId);
    }
  }

  /** The selected route in riding direction. */
  @cached
  get route(): Route | undefined {
    const r = this.baseRoute;
    return r && this.isReversed ? reversed(r) : r;
  }

  @cached
  get trip(): Trip | undefined {
    const route = this.route;
    const climate = this.atlas.climate;
    if (!route || !climate || route.points.length < 2) return undefined;
    return planTrip(route, climate, {
      start: this.start,
      kmPerDay: this.kmPerDay,
      rideDays: this.rideDays,
      restDays: this.restDays,
      rainThreshold: this.rainThreshold,
    });
  }

  addRoute(
    name: string,
    coords: { lat: number; lon: number; ele?: number | null }[],
  ): Route {
    const points = withDistances(coords);
    const route: Route = {
      id: `custom-${Date.now().toString(36)}`,
      name,
      color: CUSTOM_COLORS[this.custom.length % CUSTOM_COLORS.length]!,
      group: 'Yours',
      isPreset: false,
      points,
      towns: [],
      km: points[points.length - 1]?.km ?? 0,
    };
    this.custom.push(route);
    this.routeId = route.id;
    this.isReversed = false;
    this.save();
    return route;
  }

  deleteRoute(id: string): void {
    const i = this.custom.findIndex((r) => r.id === id);
    if (i >= 0) this.custom.splice(i, 1);
    this.save();
    if (this.routeId === id)
      void this.selectRoute(this.atlas.presets[0]?.id ?? '');
  }

  startDrawing(): void {
    this.drawn.splice(0, this.drawn.length);
    this.isDrawing = true;
  }

  addDrawnPoint(lat: number, lon: number): void {
    this.drawn.push({ lat, lon });
  }

  undoDrawnPoint(): void {
    this.drawn.pop();
  }

  cancelDrawing(): void {
    this.isDrawing = false;
    this.drawn.splice(0, this.drawn.length);
  }

  finishDrawing(name: string): void {
    if (this.drawn.length >= 2) {
      this.addRoute(name || `My route ${this.custom.length + 1}`, [
        ...this.drawn,
      ]);
    }
    this.cancelDrawing();
  }
}

declare module '@ember/service' {
  interface Registry {
    planner: PlannerService;
  }
}
