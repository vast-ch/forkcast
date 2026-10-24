import Service, { service } from '@ember/service';
import { cached, tracked } from '@glimmer/tracking';
import { TrackedArray } from 'tracked-built-ins';
import { CycleNet } from 'forkcast/utils/cyclenet';
import type AtlasService from './atlas';
import type IndexController from 'forkcast/controllers/index';
import {
  RAIN_THRESHOLDS,
  type DayClimate,
  type RainThreshold,
} from 'forkcast/utils/climate';
import { planTrip, type Trip, type TripDay } from 'forkcast/utils/itinerary';
import {
  decodeTrack,
  encodeTrack,
  reversed,
  withDistances,
  type Route,
  type RoutePoint,
} from 'forkcast/utils/route';
import {
  DEFAULTS,
  OWN_ROUTE_ID,
  inLimits,
  isIsoDate,
  type LimitedKey,
  type SettingKey,
} from 'forkcast/utils/settings';
import { WEEKS, weekOfDate, type WeekSlot } from 'forkcast/utils/weeks';

export type TempMetric = 'high' | 'low';
/** The map's optional layers, toggled in the Map section. */
export type MapDetail = 'borders' | 'cities' | 'relief' | 'water' | 'routes';
export const MAP_DETAILS: { key: MapDetail; label: string }[] = [
  { key: 'borders', label: 'Borders' },
  { key: 'cities', label: 'Cities' },
  { key: 'relief', label: 'Relief' },
  { key: 'water', label: 'Water' },
  { key: 'routes', label: 'Routes' },
];
export type RainMetric = 'mm' | 'days';

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

  /** Set by the index route (the planner); undefined outside it. */
  @tracked qp?: IndexController;

  // Interaction (not in the URL)
  @tracked hover?: Hover;
  @tracked isDrawing = false;
  /** The clicks while drawing: a sketch the route is matched to. */
  sketch = new TrackedArray<{ lat: number; lon: number }>();
  /** While drawing: follow the cycle routes between clicks, or draw straight lines. */
  @tracked snapToRoutes = true;

  private read<K extends SettingKey>(key: K): (typeof DEFAULTS)[K] {
    return this.qp ? this.qp[key] : DEFAULTS[key];
  }

  /** A numeric trip setting from the URL, or its default when out of range. */
  private limited(key: LimitedKey): number {
    const v = Number(this.read(key));
    return inLimits(key, v) ? v : DEFAULTS[key];
  }

  private write<K extends SettingKey>(
    key: K,
    value: (typeof DEFAULTS)[K],
  ): void {
    if (this.qp)
      (this.qp as unknown as Record<SettingKey, unknown>)[key] = value;
  }

  /** Continents whose climate is shown, in the order they were added. */
  get continents(): string[] {
    return this.read('continents').split(',').filter(Boolean);
  }

  /** Show another continent as well (loads its data). */
  addContinent(id: string): void {
    if (this.continents.includes(id)) return;
    this.write('continents', [...this.continents, id].join(','));
  }

  /** Quarter-month shown on the map, 0–47 */
  get week(): number {
    const w = Math.round(Number(this.read('week'))) - 1;
    return w >= 0 && w < WEEKS.length ? w : DEFAULTS.week - 1;
  }
  set week(w: number) {
    this.write('week', w + 1);
  }

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

  get tempMetric(): TempMetric {
    return this.read('temp') === 'low' ? 'low' : 'high';
  }
  set tempMetric(v: TempMetric) {
    this.write('temp', v);
  }

  get showTemp(): boolean {
    return this.read('heat');
  }
  set showTemp(v: boolean) {
    this.write('heat', v);
  }

  get showRain(): boolean {
    return this.read('rain');
  }
  set showRain(v: boolean) {
    this.write('rain', v);
  }

  /** Which map details are on (each a URL setting of the same name). */
  showDetail(key: MapDetail): boolean {
    return this.read(key);
  }

  toggleDetail(key: MapDetail): void {
    this.write(key, !this.read(key));
  }

  get rainMetric(): RainMetric {
    return this.read('dots') === 'days' ? 'days' : 'mm';
  }
  set rainMetric(v: RainMetric) {
    this.write('dots', v);
  }

  get rainThreshold(): RainThreshold {
    const v = Number(this.read('rainy'));
    return RAIN_THRESHOLDS.find((t) => t === v) ?? 5;
  }
  set rainThreshold(v: RainThreshold) {
    this.write('rainy', v);
  }

  get start(): string {
    const v = this.read('start');
    return isIsoDate(v) ? v : DEFAULTS.start;
  }
  set start(v: string) {
    this.write('start', v);
  }

  get kmPerDay(): number {
    return this.limited('km');
  }
  set kmPerDay(v: number) {
    this.write('km', v);
  }

  /** Average riding speed, km/h */
  get speed(): number {
    return this.limited('speed');
  }
  set speed(v: number) {
    this.write('speed', v);
  }

  get rideDays(): number {
    return this.limited('ride');
  }
  set rideDays(v: number) {
    this.write('ride', v);
  }

  get restDays(): number {
    return this.limited('rest');
  }
  set restDays(v: number) {
    this.write('rest', v);
  }

  get isReversed(): boolean {
    return this.read('reverse');
  }
  set isReversed(v: boolean) {
    this.write('reverse', v);
  }

  get highlightedDay(): number | undefined {
    return Number(this.read('day')) || undefined;
  }
  set highlightedDay(n: number | undefined) {
    this.write('day', n ?? 0);
  }

  /** Generic setter used by the UI. */
  set<K extends keyof this>(key: K, value: this[K]): void {
    this[key] = value;
  }

  /** Set a numeric trip setting from an input; values out of range are ignored. */
  setLimited(key: LimitedKey, value: string): void {
    const v = Number(value);
    if (inLimits(key, v)) this.write(key, v);
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
    this.highlightedDay = days.find(this.inMapWeek)?.n;
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
    if (this.highlightedDay === day.n) this.highlightedDay = undefined;
    else this.highlightDay(day);
  }

  /** Ride the route the other way; the day numbers change, so the highlight goes. */
  toggleReversed(): void {
    this.isReversed = !this.isReversed;
    this.highlightedDay = undefined;
  }

  // --- Routes ---------------------------------------------------------------

  /** Your own route, decoded from the URL. */
  @cached
  get ownRoute(): Route | undefined {
    const track = this.read('track');
    if (!track) return undefined;
    const coords = decodeTrack(track);
    if (coords.length < 2) return undefined;
    const points = withDistances(coords);
    return {
      id: OWN_ROUTE_ID,
      name: this.read('name') || 'My route',
      group: 'Yours',
      color: OWN_COLOR,
      isPreset: false,
      points,
      km: points[points.length - 1]!.km,
    };
  }

  /** Everything the route picker offers on the loaded continents. */
  @cached
  get choices(): RouteChoice[] {
    const own = this.ownRoute;
    return own ? [...this.atlas.presets, own] : this.atlas.presets;
  }

  /** The selected route id, falling back to the first preset of the loaded continents. */
  get routeId(): string {
    const id = this.read('route');
    if (id && this.choices.some((r) => r.id === id)) return id;
    return this.atlas.presets[0]?.id ?? (this.ownRoute ? OWN_ROUTE_ID : '');
  }

  /** The selected route in its original direction, once its track is loaded. */
  @cached
  get baseRoute(): Route | undefined {
    const id = this.routeId;
    if (id === OWN_ROUTE_ID) return this.ownRoute;
    return this.atlas.tracks.get(id);
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
      speed: this.speed,
      rideDays: this.rideDays,
      restDays: this.restDays,
      rainThreshold: this.rainThreshold,
    });
  }

  /** Select a route, loading its track if it is a preset. */
  async selectRoute(id: string): Promise<void> {
    const isDefault = id === (this.atlas.presets[0]?.id ?? '');
    this.write('route', isDefault ? '' : id);
    this.highlightedDay = undefined;
    await this.loadSelected();
  }

  /** Make sure the selected preset's track is loaded. */
  async loadSelected(): Promise<void> {
    const id = this.routeId;
    if (id && id !== OWN_ROUTE_ID) await this.atlas.loadRoute(id);
  }

  /** Make a drawn or imported track your route (replacing the previous one). */
  setOwnRoute(
    name: string,
    coords: { lat: number; lon: number; ele?: number | null }[],
  ): void {
    this.write('track', encodeTrack(coords));
    this.write('name', name);
    this.write('route', OWN_ROUTE_ID);
    this.write('reverse', false);
    this.highlightedDay = undefined;
  }

  deleteOwnRoute(): void {
    this.write('track', '');
    this.write('name', '');
    this.write('route', '');
    this.highlightedDay = undefined;
    void this.loadSelected();
  }

  // --- Drawing ----------------------------------------------------------------

  startDrawing(): void {
    this.sketch.splice(0, this.sketch.length);
    this.isDrawing = true;
    this.loadCycleNet();
  }

  /** Clicks so far. */
  get drawnClicks(): number {
    return this.sketch.length;
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

  /** The cycle network of the shown continents, once fetched. */
  @cached
  get cycleNet(): CycleNet | undefined {
    const files = this.atlas.loaded.flatMap((l) => {
      const data = this.atlas.detail('cyclenet', l.continent.id);
      return data ? [data] : [];
    });
    return files.length ? new CycleNet(files) : undefined;
  }

  /** Fetch the cycle network (only when drawing with snapping on). */
  loadCycleNet(): void {
    if (!this.snapToRoutes) return;
    for (const id of this.atlas.loadedIds)
      void this.atlas.loadDetail('cyclenet', id);
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

  cancelDrawing(): void {
    this.isDrawing = false;
    this.sketch.splice(0, this.sketch.length);
  }

  /** A drawn route needs at least two points. */
  get canFinishDrawing(): boolean {
    return this.sketch.length >= 2 && this.drawn.length >= 2;
  }

  finishDrawing(name: string): void {
    if (this.canFinishDrawing) {
      this.setOwnRoute(name || 'My route', [...this.drawn]);
    }
    this.cancelDrawing();
  }
}

declare module '@ember/service' {
  interface Registry {
    planner: PlannerService;
  }
}
