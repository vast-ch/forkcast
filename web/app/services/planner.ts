import Service, { service } from '@ember/service';
import { cached, tracked } from '@glimmer/tracking';
import { TrackedArray } from 'tracked-built-ins';
import { CycleNet } from 'forkcast/utils/cyclenet';
import type AtlasService from './atlas';
import type MyRoutesService from './my-routes';
import { isOwnRouteId } from './my-routes';
import type IndexController from 'forkcast/controllers/index';
import {
  CLIMATES,
  climateOn,
  tilesAlong,
  type ClimateId,
  type DayClimate,
  type RainThreshold,
} from 'forkcast/utils/climate';
import {
  planTrip,
  type Milestones,
  type Trip,
  type TripDay,
} from 'forkcast/utils/itinerary';
import {
  decodeTrack,
  reversed,
  withDistances,
  type Route,
  type RoutePoint,
} from 'forkcast/utils/route';
import {
  DEFAULTS,
  PARSE,
  inLimits,
  isIsoDate,
  type LimitedKey,
  type SettingKey,
} from 'forkcast/utils/settings';
import { WEEKS, weekOfDate, type WeekSlot } from 'forkcast/utils/weeks';

export type TempMetric = 'high' | 'low';
/** The map's optional layers, toggled in the Map section. */
export type MapDetail = 'borders' | 'relief' | 'water' | 'routes';
export const MAP_DETAILS: { key: MapDetail; label: string }[] = [
  { key: 'borders', label: 'Borders' },
  { key: 'relief', label: 'Relief' },
  { key: 'water', label: 'Water' },
  { key: 'routes', label: 'Routes' },
];
export type RainMetric = 'mm' | 'days';
export const DATE_CHOICES: { value: Milestones; label: string }[] = [
  { value: 'off', label: 'Off' },
  { value: 'months', label: 'Months' },
  { value: 'weeks', label: 'Weeks' },
];
/** How the climate switch names each climate (`CLIMATES`, in its order). */
const CLIMATE_LABELS: Record<ClimateId, { label: string; title: string }> = {
  last15: { label: '15 yrs', title: 'The average of 2011–2025' },
  last10: { label: '10 yrs', title: 'The average of 2016–2025' },
  last5: { label: '5 yrs', title: 'The average of 2021–2025' },
  last1: { label: '1 yr', title: 'Only 2025: each month as it was' },
  elnino: {
    label: 'El Niño',
    title: 'A year with El Niño: how El Niño months differed, 1981–2025',
  },
  lanina: {
    label: 'La Niña',
    title: 'A year with La Niña: how La Niña months differed, 1981–2025',
  },
};
export const CLIMATE_CHOICES = CLIMATES.map((value) => ({
  value,
  ...CLIMATE_LABELS[value],
}));

/** Which city names the map shows. */
export type CityLimit = 'top10' | 'big' | 'off';
export const CITY_CHOICES: {
  value: CityLimit;
  label: string;
  title: string;
}[] = [
  { value: 'off', label: 'Off', title: 'No city names' },
  {
    value: 'top10',
    label: '10 biggest',
    title: 'The 10 biggest in each country',
  },
  { value: 'big', label: '500k+', title: 'Every town over 500,000 people' },
];

/**
 * A setting: the index controller's query parameter of the same name, so it
 * lives in the URL. Reads are checked by its parser in `utils/settings.ts`
 * (anything else reads as the default); outside the planner route it is the
 * default and writes go nowhere.
 */
function setting(_target: object, name: string): void {
  const key = name as SettingKey;
  return {
    configurable: true,
    enumerable: true,
    get(this: PlannerService) {
      const v: unknown = this.qp?.[key];
      return PARSE[key](v) ?? DEFAULTS[key];
    },
    set(this: PlannerService, value: unknown) {
      if (this.qp)
        (this.qp as unknown as Record<SettingKey, unknown>)[key] = value;
    },
    // Legacy decorators replace the field with the descriptor returned;
    // TypeScript types them as returning nothing.
  } as unknown as void;
}

/** How far a click may be from a cycle route to be moved onto it, km. */
const CLICK_SNAP_KM = 25;

/** Colour of your own route, and of the line while drawing it. */
export const OWN_COLOR = '#b5179e';

/** What is under the mouse pointer on the map. */
export interface Hover {
  lat: number;
  lon: number;
  /** The average climate there in the week shown, if there is data */
  climate: DayClimate | null;
  /** Set when the pointer is near the selected route */
  onRoute?: {
    km: number;
    day?: TripDay;
    weather?: DayClimate;
    point: RoutePoint;
  };
}

export interface RouteChoice {
  id: string;
  name: string;
  group: string;
  km: number;
  color: string;
}

/**
 * All planner state. Settings are stored in the index controller's query
 * parameters (so they live in the URL); everything else here is transient.
 */
export default class PlannerService extends Service {
  @service declare atlas: AtlasService;
  @service('my-routes') declare myRoutes: MyRoutesService;

  /** Set by the index route (the planner); undefined outside it. */
  @tracked qp?: IndexController;

  // Interaction (not in the URL)
  @tracked hover?: Hover;
  @tracked isDrawing = false;
  /** The clicks while drawing: a sketch the route is matched to. */
  sketch = new TrackedArray<{ lat: number; lon: number }>();
  /** While drawing: follow the cycle routes between clicks, or draw straight lines. */
  @tracked snapToRoutes = true;
  /** While editing one of your routes (drawing it further, or renaming an
   * imported one): its id. */
  @tracked editingId?: string;
  /** The name in the editor while drawing or editing; applied on save. */
  @tracked draftName = '';

  // Settings (in the URL; see `setting`)
  /** Which climate's grids are loaded */
  @setting declare climate: ClimateId;
  /** Quarter-month shown on the map, 0–47 */
  @setting declare week: number;
  @setting declare tempMetric: TempMetric;
  @setting declare showTemp: boolean;
  @setting declare showRain: boolean;
  @setting declare borders: boolean;
  @setting declare relief: boolean;
  @setting declare water: boolean;
  @setting declare routes: boolean;
  /** City names on the map */
  @setting declare cities: CityLimit;
  /** Dates over the night stops on the map */
  @setting declare dates: Milestones;
  @setting declare rainMetric: RainMetric;
  @setting declare rainThreshold: RainThreshold;
  @setting declare start: string;
  @setting declare kmPerDay: number;
  /** Average riding speed, km/h */
  @setting declare speed: number;
  @setting declare rideDays: number;
  @setting declare restDays: number;
  @setting declare isReversed: boolean;
  /** The highlighted trip day's number, 0 for none */
  @setting declare highlightedDay: number;
  /** The selected route as the link has it ('' for the default); see `selectedRouteId` */
  @setting declare routeId: string;

  /** The map's quarter-month, with its dates and position in the year. */
  get weekSlot(): WeekSlot {
    return WEEKS[this.week]!;
  }

  /** Month (0–11) of the quarter-month shown on the map. */
  get month(): number {
    return this.weekSlot.month;
  }

  /** Show the quarter-month a date falls in. */
  showDate(date: Date): void {
    this.week = weekOfDate(date);
  }

  toggleDetail(key: MapDetail): void {
    this[key] = !this[key];
  }

  /** Generic setter used by the UI. */
  set<K extends keyof this>(key: K, value: this[K]): void {
    this[key] = value;
  }

  /** Set a numeric trip setting from an input; values out of range are ignored. */
  setLimited(key: LimitedKey, value: string): void {
    const v = Number(value);
    if (inLimits(key, v)) this[key] = v;
  }

  /**
   * Set the trip's first day from a date input (anything else is ignored),
   * and select that first day, so the chart and the map start there.
   */
  setStart(value: string): void {
    if (!isIsoDate(value)) return;
    this.start = value;
    const first = this.trip?.days[0];
    if (first) this.highlightDay(first);
  }

  // --- Trip days --------------------------------------------------------------

  /** Does a trip day fall in the quarter-month shown on the map? */
  private inMapWeek = (d: TripDay): boolean => weekOfDate(d.date) === this.week;

  /**
   * Show a quarter-month on the map (from the week slider) and keep the day
   * chart in step: the selected day stays if it falls in that week, otherwise
   * the trip's first day in it is selected. A week the trip doesn't reach
   * selects no day; the chart shows it as `offTrip`.
   */
  selectWeek(w: number): void {
    this.week = w;
    const days = this.trip?.days ?? [];
    const selected = days.find((d) => d.n === this.highlightedDay);
    if (selected && this.inMapWeek(selected)) return;
    this.highlightedDay = days.find(this.inMapWeek)?.n ?? 0;
  }

  /**
   * Where the map's week lies when the trip has no day in it: before the trip
   * or after it, whichever end is nearer in the year. Undefined while the week
   * is inside the trip, while a day is selected (a link can name a day from
   * another week), or when there is no trip.
   */
  get offTrip(): 'before' | 'after' | undefined {
    const days = this.trip?.days;
    const first = days?.[0];
    const last = days?.[days.length - 1];
    if (!days || !first || !last || this.highlightedDay) return undefined;
    if (days.some(this.inMapWeek)) return undefined;
    const w = this.week;
    const n = WEEKS.length;
    const toStart = (weekOfDate(first.date) - w + n) % n;
    const fromEnd = (w - weekOfDate(last.date) + n) % n;
    return toStart <= fromEnd ? 'before' : 'after';
  }

  /** Highlight a trip day and show its week on the map. */
  highlightDay(day: TripDay): void {
    this.highlightedDay = day.n;
    this.showDate(day.date);
  }

  /** Highlight a trip day, or clear the highlight if it is that day already. */
  toggleDay(day: TripDay): void {
    if (this.highlightedDay === day.n) this.highlightedDay = 0;
    else this.highlightDay(day);
  }

  /** Ride the route the other way; the day numbers change, so the highlight goes. */
  toggleReversed(): void {
    this.isReversed = !this.isReversed;
    this.highlightedDay = 0;
  }

  // --- Routes ---------------------------------------------------------------

  /** Your own routes, saved in this browser. */
  @cached
  get ownRoutes(): Route[] {
    return this.myRoutes.routes.flatMap((saved) => {
      const coords = decodeTrack(saved.track);
      if (coords.length < 2) return [];
      const points = withDistances(coords);
      return [
        {
          id: saved.id,
          name: saved.name,
          group: 'Yours',
          color: OWN_COLOR,
          isPreset: false,
          points,
          km: points[points.length - 1]!.km,
        },
      ];
    });
  }

  /** Everything the route picker offers. */
  @cached
  get choices(): RouteChoice[] {
    // A route being drawn further shows as it is now.
    const redrawn = this.isDrawing ? this.redrawnRoute : undefined;
    const own = this.ownRoutes.map((r) => (r.id === redrawn?.id ? redrawn : r));
    return [...this.atlas.presets, ...own];
  }

  /**
   * The selected route id, falling back to the first preset. A link to one of your routes keeps its id even where the
   * route isn't saved (see `isMissingRoute`).
   */
  get selectedRouteId(): string {
    const id = this.routeId;
    if (id && (isOwnRouteId(id) || this.choices.some((r) => r.id === id)))
      return id;
    return this.atlas.presets[0]?.id ?? this.ownRoutes[0]?.id ?? '';
  }

  /** The link points to someone's own route that isn't saved in this browser. */
  get isMissingRoute(): boolean {
    return isOwnRouteId(this.routeId) && !this.myRoutes.find(this.routeId);
  }

  /** The selected route, if it's one of yours: as saved. */
  get selectedOwn() {
    return this.myRoutes.find(this.selectedRouteId);
  }

  /** The selected route in its original direction, once its track is loaded. */
  @cached
  get baseRoute(): Route | undefined {
    const id = this.selectedRouteId;
    if (this.isRedrawing) return this.redrawnRoute;
    if (isOwnRouteId(id)) return this.ownRoutes.find((r) => r.id === id);
    return this.atlas.tracks.get(id);
  }

  /** Drawing the selected route further: the trip follows the new line. */
  get isRedrawing(): boolean {
    return this.isDrawing && this.editingId === this.selectedRouteId;
  }

  /** The route as it's being redrawn (not saved yet). */
  @cached
  get redrawnRoute(): Route | undefined {
    const saved = this.ownRoutes.find((r) => r.id === this.editingId);
    const line = this.drawn;
    if (!saved || line.length < 2) return undefined;
    const points = withDistances(line);
    return { ...saved, points, km: points[points.length - 1]!.km };
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
    // The tiles along the route, for the finest data; until they are in, the
    // overview answers, and the trip is planned again as each arrives.
    void this.atlas.want('route', tilesAlong(route, climate.header.tile));
    return planTrip(route, climate, {
      start: this.start,
      kmPerDay: this.kmPerDay,
      speed: this.speed,
      rideDays: this.rideDays,
      restDays: this.restDays,
      rainThreshold: this.rainThreshold,
    });
  }

  /**
   * The temperature (the map's high or low) at the route's start on a date:
   * what the first day would be like when starting then. For the start date
   * picker; undefined without a route or data there.
   */
  startTempOn(date: Date): number | undefined {
    const start = this.route?.points[0];
    const climate = this.atlas.climate;
    if (!start || !climate) return undefined;
    const t = climateOn(climate, date, start, this.rainThreshold)[
      this.tempMetric
    ];
    return Number.isNaN(t) ? undefined : t;
  }

  /** Select a route, loading its track if it is a preset. */
  async selectRoute(id: string): Promise<void> {
    const isDefault = id === (this.atlas.presets[0]?.id ?? '');
    this.routeId = isDefault ? '' : id;
    this.highlightedDay = 0;
    await this.loadSelected();
  }

  /** Make sure the selected preset's track is loaded. */
  async loadSelected(): Promise<void> {
    const id = this.selectedRouteId;
    if (id && !isOwnRouteId(id)) await this.atlas.loadRoute(id);
  }

  /** Save an imported track as one of your routes and select it. */
  importRoute(
    name: string,
    coords: { lat: number; lon: number; ele?: number | null }[],
  ): void {
    this.#selectOwn(this.myRoutes.add(coords, name).id);
  }

  #selectOwn(id: string): void {
    this.routeId = id;
    this.isReversed = false;
    this.highlightedDay = 0;
  }

  /** Delete one of your routes; if it was selected, the default comes back. */
  deleteRoute(id: string): void {
    this.myRoutes.remove(id);
    if (this.routeId === id) {
      this.routeId = '';
      this.highlightedDay = 0;
      void this.loadSelected();
    }
  }

  // --- Drawing and editing -----------------------------------------------------

  /** Drawing a new route, or editing one of yours. */
  get isEditing(): boolean {
    return this.isDrawing || this.editingId !== undefined;
  }

  /** Draw a new route, or carry on drawing one of yours (`id`). */
  startDrawing(id?: string): void {
    const saved = id ? this.myRoutes.find(id) : undefined;
    this.sketch.splice(0, this.sketch.length, ...(saved?.sketch ?? []));
    if (saved?.snap !== undefined) this.snapToRoutes = saved.snap;
    this.editingId = saved?.id;
    this.draftName = saved?.name ?? this.myRoutes.nextName();
    this.isDrawing = true;
    this.loadCycleNet();
  }

  /** Edit one of your routes: drawn ones go back into drawing, imported ones
   * (which can't be reshaped) only get their name edited. */
  editRoute(id: string): void {
    const saved = this.myRoutes.find(id);
    if (!saved) return;
    if (saved.sketch) return this.startDrawing(id);
    this.editingId = id;
    this.draftName = saved.name;
  }

  /**
   * The route being drawn: with snapping on, the cycle-network line that best
   * follows the sketch (straight where it's off the network); otherwise the
   * clicks joined with straight lines.
   */
  @cached
  get drawn(): { lat: number; lon: number }[] {
    const sketch = [...this.sketch];
    const net = this.snapToRoutes ? this.cycleNet : undefined;
    return net && sketch.length ? net.match(sketch, CLICK_SNAP_KM) : sketch;
  }

  /** The cycle network, once fetched. */
  @cached
  get cycleNet(): CycleNet | undefined {
    const data = this.atlas.detail('cyclenet');
    return data ? new CycleNet([data]) : undefined;
  }

  /** Fetch the cycle network (only when drawing with snapping on). */
  loadCycleNet(): void {
    if (this.snapToRoutes) void this.atlas.loadDetail('cyclenet');
  }

  toggleSnap(): void {
    this.snapToRoutes = !this.snapToRoutes;
    this.loadCycleNet();
  }

  addDrawnPoint(lat: number, lon: number): void {
    this.sketch.push({ lat, lon });
  }

  /** Take back the last click. */
  undoDrawnPoint(): void {
    this.sketch.pop();
  }

  /** Leave drawing or editing without saving. */
  cancelEditing(): void {
    this.isDrawing = false;
    this.editingId = undefined;
    this.draftName = '';
    this.sketch.splice(0, this.sketch.length);
  }

  /** A drawn route needs at least two points; a rename can always be saved. */
  get canSave(): boolean {
    if (!this.isDrawing) return true;
    return this.sketch.length >= 2 && this.drawn.length >= 2;
  }

  /** Save the drawing or the edit: a new route, or over the one edited. */
  saveEditing(): void {
    if (this.canSave) {
      const id = this.editingId;
      if (this.isDrawing) {
        const coords = [...this.drawn];
        const sketch = [...this.sketch];
        if (id) {
          this.myRoutes.redraw(id, coords, sketch, this.snapToRoutes);
          this.highlightedDay = 0;
        } else {
          const saved = this.myRoutes.add(coords, this.draftName, {
            sketch,
            snap: this.snapToRoutes,
          });
          this.#selectOwn(saved.id);
        }
      }
      if (id)
        this.myRoutes.rename(
          id,
          this.draftName.trim() || this.myRoutes.find(id)!.name,
        );
    }
    this.cancelEditing();
  }
}

declare module '@ember/service' {
  interface Registry {
    planner: PlannerService;
  }
}
