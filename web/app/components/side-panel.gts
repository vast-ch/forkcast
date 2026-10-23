import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn, hash } from '@ember/helper';
import { LinkTo } from '@ember/routing';
import { SegmentedControl } from 'frontile/buttons';
import { Input, Switch } from 'frontile/forms';
import type PlannerService from 'forkcast/services/planner';
import type AtlasService from 'forkcast/services/atlas';
import type { RainMetric, TempMetric } from 'forkcast/services/planner';
import type { RainThreshold } from 'forkcast/utils/climate';
import { MONTHS, tempSwatch } from 'forkcast/utils/climate';
import {
  css,
  fmtDate,
  fmtKm,
  fmtPct,
  fmtShortDate,
  fmtTemp,
  fmtWeekday,
} from 'forkcast/utils/format';
import { not } from 'forkcast/utils/helpers';
import { LIMITS } from 'forkcast/utils/settings';
import { LAST_WEEK } from 'forkcast/utils/weeks';
import { gpxName, parseGpx, toGpx } from 'forkcast/utils/route';
import type { TripDay } from 'forkcast/utils/itinerary';
import Logo from 'forkcast/components/logo';
import HelpLink from 'forkcast/components/help-link';
import ArrowsDownUp from 'ember-phosphor-icons/components/ph-arrows-down-up';

interface SidePanelSignature {
  Args: {
    /** 'all' (desktop sidebar), 'settings' (phone drawer) or 'overview' (phone page) */
    part?: 'all' | 'settings' | 'overview';
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

  get showSettings() {
    return this.part !== 'overview';
  }

  get showOverview() {
    return this.part !== 'settings';
  }

  @service declare planner: PlannerService;
  @service declare atlas: AtlasService;

  @tracked drawnName = '';
  @tracked importError?: string;

  /** Month labels under the slider, each centred on its four steps, and a
   * tick at each month's first step. */
  months = MONTHS.map((label, i) => ({
    label,
    style: css('left: ', ((i * 4 + 1.5) / LAST_WEEK) * 100, '%'),
    tickStyle: css('left: ', ((i * 4) / LAST_WEEK) * 100, '%'),
  }));

  lastWeek = LAST_WEEK;
  limits = LIMITS;

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
    const byGroup = new Map<
      string,
      { id: string; label: string; isSelected: boolean }[]
    >();
    for (const r of this.planner.choices) {
      const list = byGroup.get(r.group) ?? [];
      list.push({
        id: r.id,
        label: `${r.name} · ${fmtKm(r.km)}`,
        isSelected: r.id === this.planner.routeId,
      });
      byGroup.set(r.group, list);
    }
    return [...byGroup.entries()]
      .sort(([a], [b]) => order.indexOf(a) - order.indexOf(b))
      .map(([label, routes]) => ({ label, routes }));
  }

  get selected() {
    return this.planner.choices.find((r) => r.id === this.planner.routeId);
  }

  get isLoadingRoute() {
    return this.atlas.loadingRouteId === this.planner.routeId;
  }

  get summary() {
    const t = this.trip;
    if (!t) return undefined;
    return {
      days: t.days.length,
      riding: t.ridingDays,
      rest: t.restDays,
      end: fmtDate(t.end),
      avgHigh: fmtTemp(t.avgHigh),
      coldest: t.coldestNight ? fmtTemp(t.coldestNight.nightLow) : '–',
      coldestOn: t.coldestNight ? fmtShortDate(t.coldestNight.date) : '–',
      rainy: Math.round(t.rainyDays),
    };
  }

  get dayRows() {
    return (this.trip?.days ?? []).map((d) => ({
      d,
      date: fmtShortDate(d.date),
      weekday: fmtWeekday(d.date),
      km: d.isRest ? 'rest' : `${Math.round(d.distance)}`,
      high: fmtTemp(d.weather.high),
      low: fmtTemp(d.nightLow),
      rain: fmtPct(d.weather.rainChance),
      color: tempSwatch(d.weather.high),
      isActive: d.n === this.planner.highlightedDay,
    }));
  }

  onWeekInput = (value: string) => this.planner.set('week', Number(value));
  setTempMetric = (v: TempMetric) => this.planner.set('tempMetric', v);
  setRainMetric = (v: RainMetric) => this.planner.set('rainMetric', v);
  setRainThreshold = (v: RainThreshold) => this.planner.set('rainThreshold', v);
  toggle = (key: 'showTemp' | 'showRain', value: boolean) =>
    this.planner.set(key, value);
  toggleReversed = () => this.planner.toggleReversed();

  selectRoute = (e: Event) => {
    void this.planner.selectRoute((e.target as HTMLSelectElement).value);
  };

  deleteSelected = () => this.planner.deleteOwnRoute();
  setStart = (v: string) => this.planner.setStart(v);
  setLimited = (key: keyof typeof LIMITS, v: string) =>
    this.planner.setLimited(key, v);
  selectDay = (d: TripDay) => this.planner.toggleDay(d);

  startDrawing = () => {
    this.drawnName = '';
    this.planner.startDrawing();
  };

  setDrawnName = (v: string) => {
    this.drawnName = v;
  };

  finishDrawing = () => this.planner.finishDrawing(this.drawnName.trim());
  undoPoint = () => this.planner.undoDrawnPoint();
  cancelDrawing = () => this.planner.cancelDrawing();

  importGpx = async (e: Event) => {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    this.importError = undefined;
    try {
      const xml = await file.text();
      const coords = parseGpx(xml);
      this.planner.setOwnRoute(
        gpxName(xml) ?? file.name.replace(/\.gpx$/i, ''),
        coords,
      );
    } catch (err) {
      this.importError = err instanceof Error ? err.message : String(err);
    }
  };

  exportGpx = () => {
    const r = this.planner.route;
    if (!r) return;
    const blob = new Blob([toGpx(r)], { type: 'application/gpx+xml' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${r.name.replace(/[^\w\- ]+/g, '').trim() || 'route'}.gpx`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
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
        {{#if this.showSettings}}
          <section
            aria-labelledby="h-month"
            class="wt-sec-climate flex flex-col gap-3"
          >
            <h2 id="h-month" class="wt-h2">Climate on the map</h2>
            <div class="wt-range-wrap">
              <div class="wt-range-scale is-top" aria-hidden="true">
                <span
                  class="wt-range-value"
                  style={{this.weekLabelStyle}}
                >{{this.planner.weekSlot.label}}</span>
              </div>
              {{! `input` below is Frontile's class slot, not an event handler. }}
              {{! template-lint-disable no-passed-in-event-handlers }}
              <Input
                @type="range"
                @value={{this.weekValue}}
                @onInput={{this.onWeekInput}}
                @classes={{hash
                  innerContainer="border-0 bg-transparent p-0 shadow-none"
                  input="wt-range h-6 border-0 bg-transparent p-0 shadow-none focus:ring-0"
                }}
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
                @onChange={{fn this.toggle "showTemp"}}
              />
              <SegmentedControl
                @value={{this.planner.tempMetric}}
                @onChange={{this.setTempMetric}}
                @size="sm"
                aria-label="Temperature shown"
                as |Ctl|
              >
                <Ctl.Item @value="high">Day high</Ctl.Item>
                <Ctl.Item @value="low">Night low</Ctl.Item>
              </SegmentedControl>
            </div>
            <div class="flex items-center justify-between gap-3">
              <Switch
                @label="Rain"
                @size="sm"
                @isSelected={{this.planner.showRain}}
                @onChange={{fn this.toggle "showRain"}}
              />
              <SegmentedControl
                @value={{this.planner.rainMetric}}
                @onChange={{this.setRainMetric}}
                @size="sm"
                aria-label="Rain shown"
                as |Ctl|
              >
                <Ctl.Item @value="mm">mm</Ctl.Item>
                <Ctl.Item @value="days">Rainy days</Ctl.Item>
              </SegmentedControl>
            </div>
            <div class="flex items-center justify-between gap-3">
              <span class="text-sm">Rainy day &gt;</span>
              <SegmentedControl
                @value={{this.planner.rainThreshold}}
                @onChange={{this.setRainThreshold}}
                @size="sm"
                aria-label="Rain needed for a rainy day"
                as |Ctl|
              >
                <Ctl.Item @value={{1}}>1 mm</Ctl.Item>
                <Ctl.Item @value={{5}}>5 mm</Ctl.Item>
                <Ctl.Item @value={{10}}>10 mm</Ctl.Item>
              </SegmentedControl>
            </div>
          </section>
        {{/if}}

        {{#if this.showSettings}}
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
                    class="wt-reverse
                      {{if this.planner.isReversed 'is-active'}}"
                    aria-pressed={{if this.planner.isReversed "true" "false"}}
                    aria-label="Ride it the other way"
                    title="Ride it the other way"
                    {{on "click" this.toggleReversed}}
                  ><ArrowsDownUp class="size-5" aria-hidden="true" /></button>
                </div>
              {{else}}
                <p class="wt-empty">No preset routes here yet. Draw a route on
                  the map or import a GPX file.</p>
              {{/if}}
              <p class="wt-muted flex flex-wrap items-center gap-x-2 text-xs">
                {{#if this.isLoadingRoute}}
                  Loading the track…
                {{else if this.route}}
                  {{#if this.route.url}}
                    <a
                      href={{this.route.url}}
                      target="_blank"
                      rel="noopener noreferrer"
                      class="underline"
                    >Route page</a>
                  {{/if}}
                  {{#unless this.route.isPreset}}
                    <button
                      type="button"
                      class="wt-link-danger"
                      {{on "click" this.deleteSelected}}
                    >Delete this route</button>
                  {{/unless}}
                {{/if}}
              </p>
            </div>

            {{#if this.planner.isDrawing}}
              <div class="wt-draw flex flex-col gap-2 p-3">
                <p class="text-sm">Click the map to add points ({{this.planner.drawn.length}}
                  so far). Double-click or press Save to finish. Points are
                  joined with straight lines.</p>
                <Input
                  @label="Name"
                  @size="sm"
                  @value={{this.drawnName}}
                  @onInput={{this.setDrawnName}}
                  placeholder="My route"
                />
                <div class="flex flex-wrap gap-2">
                  <button
                    type="button"
                    class="wt-btn is-primary"
                    disabled={{not this.planner.canFinishDrawing}}
                    {{on "click" this.finishDrawing}}
                  >Save route</button>
                  <button
                    type="button"
                    class="wt-btn"
                    {{on "click" this.undoPoint}}
                  >Undo point</button>
                  <button
                    type="button"
                    class="wt-btn is-ghost"
                    {{on "click" this.cancelDrawing}}
                  >Cancel</button>
                </div>
              </div>
            {{else}}
              <div class="grid grid-cols-3 gap-2">
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
        {{/if}}

        {{! On phones the overview sits right under the day chart and needs no
            heading; the heading belongs with the trip settings. }}
        <section
          aria-labelledby={{if this.showSettings "h-trip"}}
          aria-label={{unless this.showSettings "Trip summary"}}
          class="wt-sec-trip flex flex-col gap-3"
        >
          {{#if this.showSettings}}
            <h2 id="h-trip" class="wt-h2">Trip</h2>
            <div class="grid grid-cols-3 gap-2">
              <div class="col-span-3">
                <Input
                  @label="Start"
                  @type="date"
                  @size="sm"
                  @value={{this.planner.start}}
                  @onChange={{this.setStart}}
                />
              </div>
              <div>
                <Input
                  @label="km per day"
                  @type="number"
                  @size="sm"
                  @value="{{this.planner.kmPerDay}}"
                  @onChange={{fn this.setLimited "km"}}
                  min={{this.limits.km.min}}
                  max={{this.limits.km.max}}
                  step={{this.limits.km.step}}
                />
              </div>
              <div>
                <Input
                  @label="Ride days"
                  @type="number"
                  @size="sm"
                  @value="{{this.planner.rideDays}}"
                  @onChange={{fn this.setLimited "ride"}}
                  min={{this.limits.ride.min}}
                  max={{this.limits.ride.max}}
                  step={{this.limits.ride.step}}
                />
              </div>
              <div>
                <Input
                  @label="Rest days"
                  @type="number"
                  @size="sm"
                  @value="{{this.planner.restDays}}"
                  @onChange={{fn this.setLimited "rest"}}
                  min={{this.limits.rest.min}}
                  max={{this.limits.rest.max}}
                  step={{this.limits.rest.step}}
                />
              </div>
            </div>
          {{/if}}

          {{#if this.showOverview}}{{#if this.summary}}
              <dl class="wt-summary">
                <div><dt>Days</dt><dd>{{this.summary.days}}</dd></div>
                <div><dt>Arrive</dt><dd>{{this.summary.end}}</dd></div>
                <div><dt>Riding days</dt><dd>{{this.summary.riding}}</dd></div>
                <div><dt>Rest days</dt><dd>{{this.summary.rest}}</dd></div>
                <div><dt>Average high</dt><dd
                  >{{this.summary.avgHigh}}</dd></div>
                <div><dt>Rainy riding days</dt><dd
                  >{{this.summary.rainy}}</dd></div>
                <div><dt>Coldest night</dt><dd
                  >{{this.summary.coldest}}</dd></div>
                <div><dt>Coldest night on</dt><dd
                  >{{this.summary.coldestOn}}</dd></div>
              </dl>
            {{/if}}{{/if}}
        </section>

        {{#if this.trip}}
          {{#if this.showOverview}}
            <section
              aria-labelledby="h-days"
              class="wt-sec-days flex flex-col gap-2"
            >
              <h2 id="h-days" class="wt-h2">Day by day</h2>
              <div class="wt-days" role="table" aria-label="Days of the trip">
                <div role="row" class="wt-days-head">
                  <span role="columnheader">Day</span>
                  <span role="columnheader">Date</span>
                  <span role="columnheader" class="text-right">km</span>
                  <span role="columnheader" class="text-right">High</span>
                  <span role="columnheader" class="text-right">Night</span>
                  <span role="columnheader" class="text-right">Rain</span>
                </div>
                {{#each this.dayRows as |row|}}
                  <div
                    role="row"
                    tabindex="0"
                    class="wt-days-row
                      {{if row.isActive 'is-active'}}
                      {{if row.d.isRest 'is-rest'}}"
                    {{on "click" (fn this.selectDay row.d)}}
                  >
                    <span role="cell">{{row.d.n}}</span>
                    <span role="cell"><span
                        class="wt-muted"
                      >{{row.weekday}}</span>
                      {{row.date}}</span>
                    <span role="cell" class="text-right">{{row.km}}</span>
                    <span role="cell" class="text-right"><span
                        class="wt-chip"
                        style={{css "background: " row.color}}
                      ></span>{{row.high}}</span>
                    <span role="cell" class="text-right">{{row.low}}</span>
                    <span role="cell" class="text-right">{{row.rain}}</span>
                  </div>
                {{/each}}
              </div>
            </section>
          {{/if}}
        {{/if}}
      </div>
    </aside>
  </template>
}
