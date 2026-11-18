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
  last15: { label: '15 yrs', title: '2011–2025' },
  last10: { label: '10 yrs', title: '2016–2025' },
  last5: { label: '5 yrs', title: '2021–2025' },
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

/** How many routes can be compared at once. */
export const MAX_ROUTES = 3;

/**
 * Each route's colour while comparing, by its place in the list, on the map and
 * in the day chart alike (a route alone keeps its own): apart from each other,
 * from the selected day's purple and from your own routes' magenta.
 */
export const COMPARE_COLORS = ['#17212b', '#0f7b8a', '#d9662b'];

/**
 * One of the selected routes, ridden one way, and the trip along it. Every
 * ride's trip is planned with the same settings, so day `n` is the same date
 * (and a rest day or not) on each: one selected day lines them all up.
 */
export class Ride {
  constructor(
    private planner: PlannerService,
    readonly id: string,
    readonly isReversed: boolean,
    /** Its place in the list, 0 for the first */
    readonly index: number,
  ) {}

  /** As the URL has it: the id, with `!` when ridden the other way. */
  get key(): string {
    return (this.isReversed ? '!' : '') + this.id;
  }

  /** Its colour on the map and in the chart. */
  get color(): string {
    return this.planner.isComparing
      ? COMPARE_COLORS[this.index]!
      : (this.choice?.color ?? OWN_COLOR);
  }

  /** As the route picker lists it; undefined for a link to an unsaved route. */
  get choice(): RouteChoice | undefined {
    return this.planner.choices.find((r) => r.id === this.id);
  }

  get name(): string {
    return this.choice?.name ?? 'Route not saved here';
  }

  /** Its name, and the way it's ridden when that's the other way. */
  get label(): string {
    return this.isReversed ? `${this.name} (other way)` : this.name;
  }

  /** A link to someone's own route that isn't saved in this browser. */
  get isMissing(): boolean {
    return isOwnRouteId(this.id) && !this.planner.myRoutes.find(this.id);
  }

  /** The route in its original direction, once its track is loaded; while
   * it's being drawn further, the drawing. */
  @cached
  get baseRoute(): Route | undefined {
    const p = this.planner;
    if (p.isDrawing && p.editingId === this.id) return p.redrawnRoute;
    if (isOwnRouteId(this.id)) return p.ownRoutes.find((r) => r.id === this.id);
    return p.atlas.tracks.get(this.id);
  }

  /** The route in riding direction. */
  @cached
  get route(): Route | undefined {
    const r = this.baseRoute;
    return r && this.isReversed ? reversed(r) : r;
  }

  @cached
  get trip(): Trip | undefined {
    const route = this.route;
    const climate = this.planner.atlas.climate;
    if (!route || !climate || route.points.length < 2) return undefined;
    const p = this.planner;
    return planTrip(route, climate, {
      start: p.start,
      kmPerDay: p.kmPerDay,
      speed: p.speed,
      rideDays: p.rideDays,
      restDays: p.restDays,
      rainThreshold: p.rainThreshold,
    });
  }
}

/** What is under the mouse pointer on the map. */
export interface Hover {
  lat: number;
  lon: number;
  /** The average climate there in the week shown, if there is data */
  climate: DayClimate | null;
  /** A square with climate data that isn't loaded yet (a click loads it), or is on its way */
  square?: 'unloaded' | 'loading';
  /** Set when the pointer is near a selected route */
  onRoute?: {
    /** Which route, while comparing */
    name?: string;
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
  @setting declare showWind: boolean;
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
  /** The highlighted trip day's number, 0 for none: the same day on every route */
  @setting declare highlightedDay: number;
  /** The selected routes as the link has them ('' for the default); see `rides` */
  @setting declare routeIds: string;

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
    const days = this.days;
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
    const days = this.days;
    const first = days[0];
    const last = days[days.length - 1];
    if (!first || !last || this.highlightedDay) return undefined;
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

  /**
   * Ride a route the other way (the first by default). The first route's day
   * numbers change, so the highlight goes; turning a compared route keeps the
   * day, to see that day both ways.
   */
  toggleReversed(index = 0): void {
    const ride = this.rides[index];
    if (!ride) return;
    this.#setRides(
      this.rides.map((r) =>
        r === ride ? { id: r.id, isReversed: !r.isReversed } : r,
      ),
    );
    if (index === 0) this.highlightedDay = 0;
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

  /** The routes the link names, as they are written there (see `rides`). */
  get #listed(): { id: string; isReversed: boolean }[] {
    if (!this.routeIds) return [];
    return this.routeIds.split('~').map((key) => ({
      id: key.replace(/^!/, ''),
      isReversed: key.startsWith('!'),
    }));
  }

  /** The route selected when the link names none: the first preset. */
  get #defaultId(): string {
    return this.atlas.presets[0]?.id ?? this.ownRoutes[0]?.id ?? '';
  }

  /**
   * The selected routes, the first one leading: those the link names that are
   * known here (a link to one of your routes keeps its id even where the route
   * isn't saved, see `Ride.isMissing`), each way of each at most once, up to
   * `MAX_ROUTES`; the first preset when there are none.
   */
  @cached
  get rides(): Ride[] {
    const known = new Set([
      ...this.atlas.presets.map((r) => r.id),
      ...this.ownRoutes.map((r) => r.id),
    ]);
    const seen = new Set<string>();
    const listed = this.#listed.filter(({ id, isReversed }) => {
      const key = `${isReversed ? '!' : ''}${id}`;
      if (seen.has(key) || !(known.has(id) || isOwnRouteId(id))) return false;
      seen.add(key);
      return true;
    });
    const picked = listed.length
      ? listed.slice(0, MAX_ROUTES)
      : [{ id: this.#defaultId, isReversed: false }];
    return picked.map((r, i) => new Ride(this, r.id, r.isReversed, i));
  }

  /** Write the selected routes to the URL: '' for the first preset alone. */
  #setRides(rides: { id: string; isReversed: boolean }[]): void {
    const keys = rides.map((r) => `${r.isReversed ? '!' : ''}${r.id}`);
    this.routeIds = keys.join('~') === this.#defaultId ? '' : keys.join('~');
  }

  /** More than one route selected: the map and the chart show them side by side. */
  get isComparing(): boolean {
    return this.rides.length > 1;
  }

  /** Room for another route to compare. */
  get canCompare(): boolean {
    return this.rides.length < MAX_ROUTES;
  }

  /** The first selected route, which the trip settings and the start picker follow. */
  get ride(): Ride {
    return this.rides[0]!;
  }

  /** The first selected route's id. */
  get selectedRouteId(): string {
    return this.ride.id;
  }

  /** The first selected route is ridden the other way. */
  get isReversed(): boolean {
    return this.ride.isReversed;
  }

  /** The link points to someone's own route that isn't saved in this browser. */
  get isMissingRoute(): boolean {
    return this.ride.isMissing;
  }

  /** The first selected route, if it's one of yours: as saved. */
  get selectedOwn() {
    return this.myRoutes.find(this.selectedRouteId);
  }

  /** Drawing a selected route further: its trip follows the new line. */
  get isRedrawing(): boolean {
    return this.isDrawing && this.rides.some((r) => r.id === this.editingId);
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

  /** The first selected route in riding direction. */
  get route(): Route | undefined {
    return this.ride.route;
  }

  /**
   * Each selected route's trip, in the routes' order (undefined until its
   * track is in). Asks for the climate tiles along all of them; until they
   * are in, the days have no weather, and the trips are planned again as each
   * arrives.
   */
  @cached
  get trips(): (Trip | undefined)[] {
    const climate = this.atlas.climate;
    if (climate) {
      const tiles = this.rides.flatMap((r) =>
        r.route ? tilesAlong(r.route, climate.header.tile) : [],
      );
      void this.atlas.want('route', [...new Set(tiles)]);
    }
    return this.rides.map((r) => r.trip);
  }

  /** The selected routes whose trips are planned, in order: the day chart's rows. */
  get planned(): { ride: Ride; trip: Trip }[] {
    return this.rides.flatMap((ride, i) => {
      const trip = this.trips[i];
      return trip ? [{ ride, trip }] : [];
    });
  }

  /** The first selected route's trip. */
  get trip(): Trip | undefined {
    return this.trips[0];
  }

  /**
   * The days of the longest trip: day `n` is the same date on every route, so
   * these are the days any of them has.
   */
  get days(): TripDay[] {
    let days: TripDay[] = [];
    for (const t of this.trips)
      if (t && t.days.length > days.length) days = t.days;
    return days;
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

  /**
   * Select a route as the first one, in its own direction, loading its track
   * if it is a preset; the routes compared with it stay.
   */
  async selectRoute(id: string): Promise<void> {
    const others = this.rides.slice(1).filter((r) => r.key !== id);
    this.#setRides([{ id, isReversed: false }, ...others]);
    this.highlightedDay = 0;
    await this.loadSelected();
  }

  /**
   * Add a route to compare, the way it isn't selected yet (as it is, else the
   * other way). The selected day stays: it is the same date on every route.
   */
  async compareRoute(id: string): Promise<void> {
    if (!this.canCompare) return;
    const taken = new Set(this.rides.map((r) => r.key));
    const isReversed = taken.has(id);
    if (isReversed && taken.has(`!${id}`)) return;
    this.#setRides([...this.rides, { id, isReversed }]);
    await this.loadSelected();
  }

  /** Stop comparing a route; the next one leads if it was the first. */
  removeRide(index: number): void {
    const rest = this.rides.filter((r) => r.index !== index);
    if (!rest.length) return;
    this.#setRides(rest);
    if (index === 0) this.highlightedDay = 0;
  }

  /** Make sure the selected presets' tracks are loaded. */
  async loadSelected(): Promise<void> {
    await Promise.all(
      this.rides
        .filter((r) => r.id && !isOwnRouteId(r.id))
        .map((r) => this.atlas.loadRoute(r.id)),
    );
  }

  /** Save an imported track as one of your routes and select it. */
  importRoute(
    name: string,
    coords: { lat: number; lon: number; ele?: number | null }[],
  ): void {
    this.#selectOwn(this.myRoutes.add(coords, name).id);
  }

  #selectOwn(id: string): void {
    this.#setRides([{ id, isReversed: false }, ...this.rides.slice(1)]);
    this.highlightedDay = 0;
  }

  /** Delete one of your routes; it leaves the selection, and the default
   * comes back if nothing else is left. */
  deleteRoute(id: string): void {
    this.myRoutes.remove(id);
    const rest = this.rides.filter((r) => r.id !== id);
    if (rest.length === this.rides.length) return;
    if (this.rides[0]!.id === id) this.highlightedDay = 0;
    this.#setRides(rest);
    void this.loadSelected();
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
