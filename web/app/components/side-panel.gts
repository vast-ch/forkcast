import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { waitForPromise } from '@ember/test-waiters';
import { fn } from '@ember/helper';
import { LinkTo } from '@ember/routing';
import { Button, ButtonGroup, SegmentedControl } from 'frontile/buttons';
import { DatePicker, Input, Switch } from 'frontile/forms';
import type PlannerService from 'forkcast/services/planner';
import {
  CITY_CHOICES,
  CLIMATE_CHOICES,
  MAP_DETAILS,
  MAX_ROUTES,
  DATE_CHOICES,
} from 'forkcast/services/planner';
import type { Trip } from 'forkcast/utils/itinerary';
import type AtlasService from 'forkcast/services/atlas';
import { MONTHS, RAIN_THRESHOLDS } from 'forkcast/utils/climate';
import {
  css,
  fmtDate,
  fmtKm,
  fmtRainyDays,
  fmtShortDate,
  fmtTripWind,
  fmtTemp,
} from 'forkcast/utils/format';
import { errorMessage } from 'forkcast/utils/helpers';
import { LIMITS, isoDate, type LimitedKey } from 'forkcast/utils/settings';
import { LAST_WEEK } from 'forkcast/utils/weeks';
import { gpxName, parseGpx, toGpx } from 'forkcast/utils/route';
import Logo from 'forkcast/components/logo';
import HelpLink from 'forkcast/components/help-link';
import RangeInput from 'forkcast/components/range-input';
import RouteEditor from 'forkcast/components/route-editor';
import TempCalendar from 'forkcast/components/temp-calendar';
import ArrowsDownUp from 'ember-phosphor-icons/components/ph-arrows-down-up';
import X from 'ember-phosphor-icons/components/ph-x';
import { btn, eyebrow, focusRing } from 'forkcast/utils/classes';

/** A trip at a glance, as label and value pairs. */
function tripSummary(t: Trip): { label: string; value: string }[] {
  const cold = t.lowestLow;
  return [
    ['Days', String(t.days.length)],
    ['Arrive', fmtDate(t.end)],
    ['Riding days', String(t.ridingDays)],
    ['Rest days', String(t.restDays)],
    ['High', fmtTemp(t.avgHigh)],
    ['Highest high', fmtTemp(t.likelyHighest)],
    ['Rainy riding days', fmtRainyDays(t.rainyDays, t.rainyDaysRange)],
    ['Wind', fmtTripWind(t.windSpeed, t.windPush)],
    ['Lowest low', fmtTemp(t.likelyLowest)],
    [
      'Lowest day',
      cold ? `${fmtShortDate(cold.date)}, ${fmtTemp(cold.nightLow)}` : '–',
    ],
  ].map(([label, value]) => ({ label: label!, value: value! }));
}

type MapSetting =
  | 'climate'
  | 'showTemp'
  | 'showRain'
  | 'showWind'
  | 'tempMetric'
  | 'rainMetric'
  | 'rainThreshold'
  | 'dates'
  | 'cities';

interface SidePanelSignature {
  Args: {
    /** 'all' (desktop sidebar) or 'settings' (phone drawer: no header) */
    part?: 'all' | 'settings';
  };
  Element: HTMLElement;
}

export default class SidePanel extends Component<SidePanelSignature> {
  get part() {
    return this.args.part ?? 'all';
  }

  get showHeader() {
    return this.part === 'all';
  }

  @service declare planner: PlannerService;
  @service declare atlas: AtlasService;

  @tracked importError?: string;

  /** Month labels under the slider, each centred on its four steps, and a
   * tick at each month's first step. */
  months = MONTHS.map((label, i) => ({
    label,
    style: css('left: ', ((i * 4 + 1.5) / LAST_WEEK) * 100, '%'),
    tickStyle: css('left: ', ((i * 4) / LAST_WEEK) * 100, '%'),
  }));

  lastWeek = LAST_WEEK;
  /** "Sat 24 Oct 2026" in the picker's field. */
  startFormat: Intl.DateTimeFormatOptions = {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  };
  rainThresholds = RAIN_THRESHOLDS;

  /** The time-of-year slider's rows of labels and ticks, placed by `left`. */
  rangeScale =
    'absolute inset-x-4 *:absolute *:-translate-x-1/2 *:whitespace-nowrap';

  /** The sections' headings: full-width bands, so each section (route, trip,
   * map) reads as its own block; inside the phone drawer, rounded instead. */
  heading =
    '-mx-5 border-y border-wt-line bg-wt-band px-5 py-[0.45rem] font-display text-[0.8rem] font-bold tracking-[0.08em] text-wt-ink uppercase in-[[role=dialog]]:mx-0 in-[[role=dialog]]:rounded-md in-[[role=dialog]]:border-0 in-[[role=dialog]]:px-3';
  dateChoices = DATE_CHOICES;
  cityChoices = CITY_CHOICES;
  climateChoices = CLIMATE_CHOICES;

  get weekValue() {
    return String(this.planner.week);
  }

  /** Keeps the week label above the slider's thumb. */
  get weekLabelStyle() {
    return css('left: ', (this.planner.week / LAST_WEEK) * 100, '%');
  }

  get trip() {
    return this.planner.trip;
  }

  get route() {
    return this.planner.route;
  }

  get groups() {
    const order = ['Demo', 'EuroVelo', 'Yours'];
    const label = (g: string) => (g === 'Yours' ? 'Your routes' : g);
    const byGroup = new Map<
      string,
      { id: string; label: string; isSelected: boolean }[]
    >();
    for (const r of this.planner.choices) {
      const list = byGroup.get(r.group) ?? [];
      list.push({
        id: r.id,
        label: `${r.name} · ${fmtKm(r.km)}`,
        isSelected: r.id === this.planner.selectedRouteId,
      });
      byGroup.set(r.group, list);
    }
    return [...byGroup.entries()]
      .sort(([a], [b]) => order.indexOf(a) - order.indexOf(b))
      .map(([group, routes]) => ({ label: label(group), routes }));
  }

  get isLoadingRoute() {
    return this.atlas.loadingRouteId === this.planner.selectedRouteId;
  }

  /** The trip at a glance, while there's one route. */
  get summary() {
    const t = this.trip;
    return t && !this.planner.isComparing ? tripSummary(t) : [];
  }

  /** While comparing: the trips at a glance, a column per route. */
  get comparedSummary() {
    const planned = this.planner.planned;
    if (!this.planner.isComparing || !planned.length) return undefined;
    const each = planned.map(({ trip }) => tripSummary(trip));
    return {
      routes: planned.map(({ ride }) => ({
        key: ride.key,
        label: ride.label,
        swatch: css('background: ', ride.color),
      })),
      rows: each[0]!.map(({ label }, i) => ({
        label,
        values: each.map((s) => s[i]!.value),
      })),
    };
  }

  /** The routes compared with the first, each with its own controls. */
  get compared() {
    return this.planner.rides.slice(1).map((r) => ({
      key: r.key,
      label: r.label,
      km: r.choice ? fmtKm(r.choice.km) : '',
      isReversed: r.isReversed,
      isMissing: r.isMissing,
      isLoading: this.atlas.loadingRouteId === r.id,
      swatch: css('background: ', r.color),
      toggleReversed: () => this.planner.toggleReversed(r.index),
      remove: () => this.planner.removeRide(r.index),
    }));
  }

  maxRoutes = MAX_ROUTES;

  /** The first route's colour beside the picker. */
  get selectedSwatch() {
    return css('background: ', this.planner.ride.color);
  }

  /** The map's optional layers, as toggle buttons. */
  get mapDetails() {
    return MAP_DETAILS.map(({ key, label }) => ({
      label,
      isOn: this.planner[key],
      toggle: () => this.planner.toggleDetail(key),
    }));
  }

  /** The numeric trip settings, with their allowed ranges. */
  get tripFields() {
    const p = this.planner;
    const fields: { key: LimitedKey; label: string; value: number }[] = [
      { key: 'kmPerDay', label: 'km per day', value: p.kmPerDay },
      { key: 'speed', label: 'Avg speed (km/h)', value: p.speed },
      { key: 'rideDays', label: 'Ride days', value: p.rideDays },
      { key: 'restDays', label: 'Rest days', value: p.restDays },
    ];
    return fields.map((f) => ({
      ...f,
      value: String(f.value),
      limits: LIMITS[f.key],
      onChange: (v: string) => p.setLimited(f.key, v),
    }));
  }

  onWeekInput = (value: string) => this.planner.selectWeek(Number(value));
  /** For the map's switches and segmented controls: `(fn this.setMap "showRain")`. */
  // Each control passes its own setting's type of value; `fn` can't carry that.
  setMap = (key: MapSetting, value: unknown) =>
    this.planner.set(key, value as never);
  toggleReversed = () => this.planner.toggleReversed();

  selectRoute = (e: Event) => {
    void this.planner.selectRoute((e.target as HTMLSelectElement).value);
  };

  /** From the Compare with… picker, which goes back to its prompt. */
  compareRoute = (e: Event) => {
    const select = e.target as HTMLSelectElement;
    const id = select.value;
    select.value = '';
    if (id) void this.planner.compareRoute(id);
  };

  deleteSelected = () => this.planner.deleteRoute(this.planner.selectedRouteId);
  editSelected = () => this.planner.editRoute(this.planner.selectedRouteId);
  /** From the date picker: a Date (or null if cleared, which it can't be here). */
  setStart = (d: Date | null) => {
    if (d) this.planner.setStart(isoDate(d));
  };
  /** The picker's Today button: through the picker, like a click on the day. */
  pickToday = (setValue: (d: Date) => void) => setValue(new Date());

  /** The start picker's days: the temperature at the route's start. */
  startTempOn = (date: Date) => this.planner.startTempOn(date);

  get startTempLabel() {
    return `${this.planner.tempMetric === 'high' ? 'High' : 'Low'} at the start`;
  }

  startDrawing = () => this.planner.startDrawing();

  importGpx = async (e: Event) => {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    this.importError = undefined;
    try {
      const xml = await waitForPromise(file.text());
      const coords = parseGpx(xml);
      this.planner.importRoute(
        gpxName(xml) ?? file.name.replace(/\.gpx$/i, ''),
        coords,
      );
    } catch (err) {
      this.importError = errorMessage(err);
    }
  };

  /** The last export's file URL, freed by the next export (the browser may
   * still be saving it right after the click). */
  #exportUrl?: string;

  exportGpx = () => {
    const r = this.planner.route;
    if (!r) return;
    if (this.#exportUrl) URL.revokeObjectURL(this.#exportUrl);
    const blob = new Blob([toGpx(r)], { type: 'application/gpx+xml' });
    const a = document.createElement('a');
    a.href = this.#exportUrl = URL.createObjectURL(blob);
    a.download = `${r.name.replace(/[^\w\- ]+/g, '').trim() || 'route'}.gpx`;
    a.click();
  };

  <template>
    {{! In the phone drawer, the drawer's own background and padding. }}
    <aside
      class="wt-panel flex min-h-0 flex-col bg-wt-paper in-[[role=dialog]]:bg-transparent"
      ...attributes
    >
      {{#if this.showHeader}}
        <header class="px-5 pt-5 pb-4">
          <div class="flex items-baseline justify-between gap-3">
            <h1><LinkTo @route="index" aria-label="Forkcast home"><Logo
                /></LinkTo></h1>
            <HelpLink />
          </div>
        </header>
      {{/if}}

      <div
        class="wt-panel-scroll flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto px-5 pb-6 in-[[role=dialog]]:px-0"
      >
        <section aria-labelledby="h-route" class="flex flex-col gap-3">
          <h2 id="h-route" class={{this.heading}}>Route</h2>
          <div class="flex flex-col gap-1.5">
            <label for="route-picker" class="sr-only">Route</label>
            {{#if this.groups.length}}
              <div class="flex items-stretch gap-2">
                <div
                  class="flex min-w-0 flex-1 items-stretch gap-2.5 rounded-md border border-wt-ink bg-white px-2 py-[0.35rem] focus-within:outline-2 focus-within:outline-offset-1 focus-within:outline-wt-accent"
                >
                  <span
                    class="w-[0.35rem] self-stretch rounded-xs"
                    style={{this.selectedSwatch}}
                  ></span>
                  <select
                    id="route-picker"
                    class="min-w-0 flex-1 cursor-pointer border-0 bg-transparent py-[0.2rem] font-medium text-wt-ink focus-visible:outline-none"
                    {{on "change" this.selectRoute}}
                  >
                    {{#if this.planner.isMissingRoute}}
                      <option selected disabled>Route not saved here</option>
                    {{/if}}
                    {{#each this.groups as |g|}}
                      <optgroup label={{g.label}}>
                        {{#each g.routes as |r|}}
                          <option
                            value={{r.id}}
                            selected={{r.isSelected}}
                          >{{r.label}}</option>
                        {{/each}}
                      </optgroup>
                    {{/each}}
                  </select>
                </div>
                <button
                  type="button"
                  class="inline-grid w-[2.6rem] flex-none cursor-pointer place-items-center rounded-md border
                    {{focusRing}}
                    {{if
                      this.planner.isReversed
                      'border-wt-ink bg-wt-ink text-white'
                      'border-wt-line bg-white text-wt-ink hover:border-wt-ink'
                    }}"
                  aria-pressed={{if this.planner.isReversed "true" "false"}}
                  aria-label="Ride it the other way"
                  title="Ride it the other way"
                  {{on "click" this.toggleReversed}}
                ><ArrowsDownUp class="size-5" aria-hidden="true" /></button>
              </div>
            {{else}}
              <p
                class="rounded-md border border-dashed border-wt-line px-3 py-2.5 text-[0.85rem] text-wt-muted"
              >No preset routes here yet. Draw a route on the map or import a
                GPX file.</p>
            {{/if}}
            {{#if this.planner.isMissingRoute}}
              <p class="text-sm text-wt-danger" role="alert">This link points to
                a route someone drew or imported. Those are saved only in the
                browser where they were made, so it can't be shown here: ask for
                its GPX file (Export GPX) and import it.</p>
            {{else if this.isLoadingRoute}}
              <p class="text-xs text-wt-muted">Loading the track…</p>
            {{else if this.route.url}}
              <p class="text-xs text-wt-muted"><a
                  href={{this.route.url}}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="underline"
                >Route page</a></p>
            {{/if}}
            {{#if this.planner.myRoutes.saveError}}
              <p class="text-sm text-wt-danger" role="alert">
                {{this.planner.myRoutes.saveError}}</p>
            {{/if}}
            {{#if this.planner.selectedOwn}}
              {{#unless this.planner.isEditing}}
                <p class="flex flex-wrap items-center gap-x-3 text-xs">
                  <button
                    type="button"
                    class="p-1 text-wt-accent hover:underline"
                    {{on "click" this.editSelected}}
                  >Edit route</button>
                  <button
                    type="button"
                    class="p-1 text-wt-danger hover:underline"
                    {{on "click" this.deleteSelected}}
                  >Delete this route</button>
                </p>
              {{/unless}}
            {{/if}}
          </div>

          {{#if this.groups.length}}
            {{! Routes to compare with the first: each on the map in its
                colour, with its own band in the day chart. }}
            <div class="flex flex-col gap-1.5">
              {{#each this.compared key="key" as |c|}}
                <div class="wt-compared flex items-stretch gap-2">
                  <div
                    class="flex min-w-0 flex-1 items-center gap-2.5 rounded-md border border-wt-line bg-white px-2 py-[0.35rem] text-[0.9rem]"
                  >
                    <span
                      class="w-[0.35rem] self-stretch rounded-xs"
                      style={{c.swatch}}
                    ></span>
                    <span class="min-w-0 flex-1 truncate">{{c.label}}</span>
                    {{#if c.isLoading}}
                      <span class="text-xs text-wt-muted">Loading…</span>
                    {{else if c.km}}
                      <span
                        class="font-data text-xs text-wt-muted"
                      >{{c.km}}</span>
                    {{/if}}
                  </div>
                  <button
                    type="button"
                    class="inline-grid w-[2.6rem] flex-none cursor-pointer place-items-center rounded-md border
                      {{focusRing}}
                      {{if
                        c.isReversed
                        'border-wt-ink bg-wt-ink text-white'
                        'border-wt-line bg-white text-wt-ink hover:border-wt-ink'
                      }}"
                    aria-pressed={{if c.isReversed "true" "false"}}
                    aria-label="Ride {{c.label}} the other way"
                    title="Ride it the other way"
                    {{on "click" c.toggleReversed}}
                  ><ArrowsDownUp class="size-5" aria-hidden="true" /></button>
                  <button
                    type="button"
                    class="inline-grid w-[2.6rem] flex-none cursor-pointer place-items-center rounded-md border border-wt-line bg-white text-wt-ink hover:border-wt-ink
                      {{focusRing}}"
                    aria-label="Stop comparing {{c.label}}"
                    title="Stop comparing"
                    {{on "click" c.remove}}
                  ><X class="size-4" aria-hidden="true" /></button>
                </div>
                {{#if c.isMissing}}
                  <p class="text-xs text-wt-danger">This one was drawn or
                    imported in another browser, so it can't be shown here.</p>
                {{/if}}
              {{/each}}
              {{#if this.planner.canCompare}}
                <label for="compare-picker" class="sr-only">Compare with</label>
                <select
                  id="compare-picker"
                  class="cursor-pointer rounded-md border border-dashed border-wt-line bg-white px-2 py-[0.4rem] text-[0.9rem] text-wt-muted hover:border-wt-ink
                    {{focusRing}}"
                  {{on "change" this.compareRoute}}
                >
                  <option value="" selected>Compare with…</option>
                  {{#each this.groups as |g|}}
                    <optgroup label={{g.label}}>
                      {{#each g.routes as |r|}}
                        <option value={{r.id}}>{{r.label}}</option>
                      {{/each}}
                    </optgroup>
                  {{/each}}
                </select>
              {{else}}
                <p class="text-xs text-wt-muted">Up to
                  {{this.maxRoutes}}
                  routes side by side.</p>
              {{/if}}
            </div>
          {{/if}}

          {{#if this.planner.isEditing}}
            <RouteEditor class="bg-wt-draw-soft p-3" />
          {{else}}
            {{! On phones one per row, full width: three across wrap. }}
            <div class="grid grid-cols-3 gap-2 max-desktop:grid-cols-1">
              <button
                type="button"
                class="{{btn}} justify-center"
                {{on "click" this.startDrawing}}
              >Draw a route</button>
              <label class="{{btn}} justify-center">
                Import GPX
                <input
                  type="file"
                  accept=".gpx,application/gpx+xml"
                  class="sr-only"
                  {{on "change" this.importGpx}}
                />
              </label>
              <button
                type="button"
                class="{{btn}} justify-center"
                {{on "click" this.exportGpx}}
              >Export GPX</button>
            </div>
          {{/if}}
          {{#if this.importError}}
            <p
              class="text-sm text-wt-danger"
              role="alert"
            >{{this.importError}}</p>
          {{/if}}
        </section>

        <section aria-labelledby="h-trip" class="flex flex-col gap-3">
          <h2 id="h-trip" class={{this.heading}}>Trip</h2>
          <div class="grid grid-cols-2 gap-2">
            <div class="col-span-2">
              <DatePicker
                @id="start-date"
                @label="Start"
                @inputSize="sm"
                @value={{this.planner.start}}
                @onChange={{this.setStart}}
                @weekStartsOn={{1}}
                @formatOptions={{this.startFormat}}
              >
                <:calendar as |cal|>
                  <TempCalendar
                    @color={{cal.color}}
                    @value={{cal.value}}
                    @onChange={{cal.onChange}}
                    @locale={{cal.locale}}
                    @labelledBy={{cal.labelledBy}}
                    @autofocus={{cal.autofocus}}
                    @tempOn={{this.startTempOn}}
                    @tempLabel={{this.startTempLabel}}
                    class="p-2"
                  />
                </:calendar>
                <:footer as |f|>
                  <Button
                    @variant="subtle"
                    @color="primary"
                    @size="xs"
                    @onPress={{fn this.pickToday f.setValue}}
                  >Today</Button>
                </:footer>
              </DatePicker>
            </div>
            {{#each this.tripFields as |f|}}
              <div>
                <Input
                  @label={{f.label}}
                  @type="number"
                  @size="sm"
                  @value={{f.value}}
                  @onChange={{f.onChange}}
                  min={{f.limits.min}}
                  max={{f.limits.max}}
                  step={{f.limits.step}}
                />
              </div>
            {{/each}}
          </div>

          {{#if this.comparedSummary}}
            {{! A column per route, in the routes' order. }}
            <div
              class="overflow-x-auto rounded-md border border-wt-line bg-white p-3"
            >
              <table
                class="wt-summary-compare w-full text-[0.85rem] tabular-nums [&_td]:py-1 [&_td]:pl-2 [&_td]:font-medium [&_th]:py-1 [&_th]:text-left [&_th]:align-bottom"
              >
                <thead>
                  <tr>
                    <td></td>
                    {{#each this.comparedSummary.routes key="key" as |r|}}
                      <th scope="col" class="pl-2 text-xs font-medium">
                        <span
                          class="mb-1 block h-[0.3rem] w-6 rounded-xs"
                          style={{r.swatch}}
                        ></span>{{r.label}}</th>
                    {{/each}}
                  </tr>
                </thead>
                <tbody>
                  {{#each this.comparedSummary.rows as |row|}}
                    <tr class="border-t border-wt-line">
                      <th scope="row" class={{eyebrow}}>{{row.label}}</th>
                      {{#each row.values as |v|}}
                        <td>{{v}}</td>
                      {{/each}}
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          {{/if}}
          {{#if this.summary.length}}
            <dl
              class="wt-summary grid grid-cols-2 gap-x-4 gap-y-3 rounded-md border border-wt-line bg-white p-3"
            >
              {{#each this.summary as |item|}}
                {{! Values in the body font with tabular figures: monospace
                    made dates like "Thu 4 Feb" look like a different typeface
                    from the numbers. }}
                <div><dt class={{eyebrow}}>{{item.label}}</dt><dd
                    class="text-base font-medium tabular-nums"
                  >{{item.value}}</dd></div>
              {{/each}}
            </dl>
          {{/if}}
        </section>

        <section aria-labelledby="h-map" class="flex flex-col gap-3">
          <h2 id="h-map" class={{this.heading}}>Map</h2>
          <div class="flex min-w-0 flex-col gap-1.5">
            <span class="text-sm">Climate</span>
            {{! Full width; on a narrow panel it scrolls sideways instead of widening it. }}
            <div class="min-w-0 overflow-x-auto">
              <SegmentedControl
                @value={{this.planner.climate}}
                @onChange={{fn this.setMap "climate"}}
                @size="sm"
                @isFullWidth={{true}}
                class="w-full min-w-max"
                aria-label="Climate"
                as |Ctl|
              >
                {{#each this.climateChoices as |c|}}
                  <Ctl.Item
                    @value={{c.value}}
                    title={{c.title}}
                  >{{c.label}}</Ctl.Item>
                {{/each}}
              </SegmentedControl>
            </div>
          </div>
          {{! Time of year: 48 quarter-month steps, the chosen one named above
              the thumb, month names below the track. Both scales are inset by
              the padding plus half the thumb, so 0% and 100% sit on the
              thumb's centre at either end. }}
          <div class="relative isolate px-2 pt-[1.4rem] pb-[1.1rem]">
            <div class="{{this.rangeScale}} top-0 h-4" aria-hidden="true">
              <span
                class="text-[0.8rem] font-semibold text-wt-ink"
                style={{this.weekLabelStyle}}
              >{{this.planner.weekSlot.label}}</span>
            </div>
            <RangeInput
              @value={{this.weekValue}}
              @onInput={{this.onWeekInput}}
              min="0"
              max={{this.lastWeek}}
              step="1"
              aria-label="Time of year"
              aria-valuetext={{this.planner.weekSlot.label}}
            />
            {{! Month starts: behind the input, taller than the track, so they
                show above and below it and the thumb slides over them. The
                input is 1.5rem high below 1.4rem of padding, so the track's
                centre is at 2.15rem. }}
            <div
              class="{{this.rangeScale}} top-[calc(2.15rem-7px)] -z-1 h-[14px]"
              aria-hidden="true"
            >
              {{#each this.months as |m|}}
                <span
                  class="h-full w-px bg-wt-rule"
                  style={{m.tickStyle}}
                ></span>
              {{/each}}
            </div>
            <div class="{{this.rangeScale}} bottom-0 h-4" aria-hidden="true">
              {{#each this.months as |m|}}
                <span
                  class="text-[0.7rem] text-wt-muted"
                  style={{m.style}}
                >{{m.label}}</span>
              {{/each}}
            </div>
          </div>

          <div class="flex items-center justify-between gap-3">
            <Switch
              @label="Temperature"
              @size="sm"
              @isSelected={{this.planner.showTemp}}
              @onChange={{fn this.setMap "showTemp"}}
            />
            <SegmentedControl
              @value={{this.planner.tempMetric}}
              @onChange={{fn this.setMap "tempMetric"}}
              @size="sm"
              aria-label="Temperature shown"
              as |Ctl|
            >
              <Ctl.Item @value="high">High</Ctl.Item>
              <Ctl.Item @value="low">Low</Ctl.Item>
            </SegmentedControl>
          </div>
          <div class="flex items-center justify-between gap-3">
            <Switch
              @label="Rain"
              @size="sm"
              @isSelected={{this.planner.showRain}}
              @onChange={{fn this.setMap "showRain"}}
            />
            <SegmentedControl
              @value={{this.planner.rainMetric}}
              @onChange={{fn this.setMap "rainMetric"}}
              @size="sm"
              aria-label="Rain shown"
              as |Ctl|
            >
              <Ctl.Item @value="mm">mm</Ctl.Item>
              <Ctl.Item @value="days">Rainy days</Ctl.Item>
            </SegmentedControl>
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class="text-sm">Rainy day</span>
            <span class="flex items-center gap-2">
              <span class="text-sm" aria-hidden="true">&gt;</span>
              <SegmentedControl
                @value={{this.planner.rainThreshold}}
                @onChange={{fn this.setMap "rainThreshold"}}
                @size="sm"
                aria-label="Rain needed for a rainy day"
                as |Ctl|
              >
                {{#each this.rainThresholds as |mm|}}
                  <Ctl.Item @value={{mm}}>{{mm}}mm</Ctl.Item>
                {{/each}}
              </SegmentedControl>
            </span>
          </div>
          <div class="flex items-center justify-between gap-3">
            <Switch
              @label="Wind"
              @size="sm"
              @isSelected={{this.planner.showWind}}
              @onChange={{fn this.setMap "showWind"}}
            />
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class="text-sm">Dates on the route</span>
            <SegmentedControl
              @value={{this.planner.dates}}
              @onChange={{fn this.setMap "dates"}}
              @size="sm"
              aria-label="Dates on the route"
              as |Ctl|
            >
              {{#each this.dateChoices as |c|}}
                <Ctl.Item @value={{c.value}}>{{c.label}}</Ctl.Item>
              {{/each}}
            </SegmentedControl>
          </div>
          <div class="flex items-center justify-between gap-3">
            <span class="text-sm">Cities</span>
            <SegmentedControl
              @value={{this.planner.cities}}
              @onChange={{fn this.setMap "cities"}}
              @size="sm"
              aria-label="City names shown"
              as |Ctl|
            >
              {{#each this.cityChoices as |c|}}
                <Ctl.Item
                  @value={{c.value}}
                  title={{c.title}}
                >{{c.label}}</Ctl.Item>
              {{/each}}
            </SegmentedControl>
          </div>
          <ButtonGroup
            @size="xs"
            {{! Quieter than Frontile's default (black when on): white when
                off, a soft teal when on; one equal column per toggle, filling
                the panel's width (over the group's own inline-flex). }}
            class="grid! auto-cols-[minmax(0,1fr)] grid-flow-col [&_button]:h-7 [&_button]:justify-center [&_button]:border-wt-line [&_button]:bg-white [&_button]:text-xs [&_button]:font-medium [&_button]:text-wt-muted [&_button]:shadow-none [&_button:hover]:bg-wt-band [&_button[aria-pressed=true]]:border-wt-accent/35 [&_button[aria-pressed=true]]:bg-wt-accent-soft [&_button[aria-pressed=true]]:text-wt-accent"
            role="group"
            aria-label="Show on the map"
            as |Group|
          >
            {{#each this.mapDetails as |d|}}
              <Group.ToggleButton
                @isSelected={{d.isOn}}
                @onChange={{d.toggle}}
              >{{d.label}}</Group.ToggleButton>
            {{/each}}
          </ButtonGroup>
        </section>
      </div>
    </aside>
  </template>
}
