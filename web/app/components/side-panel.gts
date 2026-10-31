import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { waitForPromise } from '@ember/test-waiters';
import { fn } from '@ember/helper';
import { LinkTo } from '@ember/routing';
import { ButtonGroup, SegmentedControl } from 'frontile/buttons';
import { DatePicker, Input, Switch } from 'frontile/forms';
import type PlannerService from 'forkcast/services/planner';
import {
  CITY_CHOICES,
  CLIMATE_CHOICES,
  MAP_DETAILS,
  DATE_CHOICES,
} from 'forkcast/services/planner';
import type AtlasService from 'forkcast/services/atlas';
import { MONTHS, RAIN_THRESHOLDS } from 'forkcast/utils/climate';
import {
  css,
  fmtDate,
  fmtHeadwind,
  fmtKm,
  fmtRainyDays,
  fmtShortDate,
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

  get selected() {
    return this.planner.choices.find(
      (r) => r.id === this.planner.selectedRouteId,
    );
  }

  get isLoadingRoute() {
    return this.atlas.loadingRouteId === this.planner.selectedRouteId;
  }

  /** The trip at a glance, as label and value pairs. */
  get summary() {
    const t = this.trip;
    if (!t) return [];
    const cold = t.lowestLow;
    return [
      ['Days', t.days.length],
      ['Arrive', fmtDate(t.end)],
      ['Riding days', t.ridingDays],
      ['Rest days', t.restDays],
      ['Average high', fmtTemp(t.avgHigh)],
      ['Highest high, likely', fmtTemp(t.likelyHighest)],
      ['Rainy riding days', fmtRainyDays(t.rainyDays, t.rainyDaysRange)],
      ['Wind', fmtHeadwind(t.headwind)],
      ['Lowest low, likely', fmtTemp(t.likelyLowest)],
      ['Lowest average low', cold ? fmtTemp(cold.nightLow) : '–'],
      ['Lowest average low on', cold ? fmtShortDate(cold.date) : '–'],
    ].map(([label, value]) => ({ label, value }));
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

  deleteSelected = () => this.planner.deleteRoute(this.planner.selectedRouteId);
  editSelected = () => this.planner.editRoute(this.planner.selectedRouteId);
  /** From the date picker: a Date (or null if cleared, which it can't be here). */
  setStart = (d: Date | null) => {
    if (d) this.planner.setStart(isoDate(d));
  };

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
    <aside class="wt-panel flex min-h-0 flex-col" ...attributes>
      {{#if this.showHeader}}
        <header class="wt-brand px-5 pt-5 pb-4">
          <div class="flex items-baseline justify-between gap-3">
            <h1 class="wt-logo-heading"><LinkTo
                @route="index"
                aria-label="Forkcast home"
              ><Logo /></LinkTo></h1>
            <HelpLink />
          </div>
        </header>
      {{/if}}

      <div
        class="wt-panel-scroll flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto px-5 pb-6"
      >
        <section
          aria-labelledby="h-route"
          class="wt-sec-route flex flex-col gap-3"
        >
          <h2 id="h-route" class="wt-h2">Route</h2>
          <div class="flex flex-col gap-1.5">
            <label for="route-picker" class="sr-only">Route</label>
            {{#if this.groups.length}}
              <div class="flex items-stretch gap-2">
                <div class="wt-select min-w-0 flex-1">
                  <span
                    class="wt-route-swatch"
                    style={{css
                      "background: "
                      (if this.selected this.selected.color "transparent")
                    }}
                  ></span>
                  <select id="route-picker" {{on "change" this.selectRoute}}>
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
                  class="wt-reverse {{if this.planner.isReversed 'is-active'}}"
                  aria-pressed={{if this.planner.isReversed "true" "false"}}
                  aria-label="Ride it the other way"
                  title="Ride it the other way"
                  {{on "click" this.toggleReversed}}
                ><ArrowsDownUp class="size-5" aria-hidden="true" /></button>
              </div>
            {{else}}
              <p class="wt-empty">No preset routes here yet. Draw a route on the
                map or import a GPX file.</p>
            {{/if}}
            {{#if this.planner.isMissingRoute}}
              <p class="wt-error text-sm" role="alert">This link points to a
                route someone drew or imported. Those are saved only in the
                browser where they were made, so it can't be shown here: ask for
                its GPX file (Export GPX) and import it.</p>
            {{else if this.isLoadingRoute}}
              <p class="wt-muted text-xs">Loading the track…</p>
            {{else if this.route.url}}
              <p class="wt-muted text-xs"><a
                  href={{this.route.url}}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="underline"
                >Route page</a></p>
            {{/if}}
            {{#if this.planner.myRoutes.saveError}}
              <p class="wt-error text-sm" role="alert">
                {{this.planner.myRoutes.saveError}}</p>
            {{/if}}
            {{#if this.planner.selectedOwn}}
              {{#unless this.planner.isEditing}}
                <p class="flex flex-wrap items-center gap-x-3 text-xs">
                  <button
                    type="button"
                    class="wt-link"
                    {{on "click" this.editSelected}}
                  >Edit route</button>
                  <button
                    type="button"
                    class="wt-link-danger"
                    {{on "click" this.deleteSelected}}
                  >Delete this route</button>
                </p>
              {{/unless}}
            {{/if}}
          </div>

          {{#if this.planner.isEditing}}
            <RouteEditor class="wt-draw p-3" />
          {{else}}
            <div class="wt-route-actions grid grid-cols-3 gap-2">
              <button
                type="button"
                class="wt-btn justify-center"
                {{on "click" this.startDrawing}}
              >Draw a route</button>
              <label class="wt-btn justify-center">
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
                class="wt-btn justify-center"
                {{on "click" this.exportGpx}}
              >Export GPX</button>
            </div>
          {{/if}}
          {{#if this.importError}}
            <p class="wt-error text-sm" role="alert">{{this.importError}}</p>
          {{/if}}
        </section>

        <section
          aria-labelledby="h-trip"
          class="wt-sec-trip flex flex-col gap-3"
        >
          <h2 id="h-trip" class="wt-h2">Trip</h2>
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

          {{#if this.summary.length}}
            <dl class="wt-summary">
              {{#each this.summary as |item|}}
                <div><dt>{{item.label}}</dt><dd>{{item.value}}</dd></div>
              {{/each}}
            </dl>
          {{/if}}
        </section>

        <section aria-labelledby="h-map" class="wt-sec-map flex flex-col gap-3">
          <h2 id="h-map" class="wt-h2">Map</h2>
          <div class="flex min-w-0 flex-col gap-1.5">
            <span class="text-sm">Climate</span>
            {{! Full width; on a narrow panel it scrolls sideways instead of widening it. }}
            <div class="wt-climate-scroll min-w-0 overflow-x-auto">
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
          <div class="wt-range-wrap">
            <div class="wt-range-scale is-top" aria-hidden="true">
              <span
                class="wt-range-value"
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
            <div class="wt-range-scale is-ticks" aria-hidden="true">
              {{#each this.months as |m|}}
                <span class="wt-range-tick" style={{m.tickStyle}}></span>
              {{/each}}
            </div>
            <div class="wt-range-scale is-bottom" aria-hidden="true">
              {{#each this.months as |m|}}
                <span
                  class="wt-range-month"
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
            <span class="wt-muted text-xs">prevailing, while riding</span>
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
            class="wt-detail-toggles"
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
