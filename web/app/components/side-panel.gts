import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { LinkTo } from '@ember/routing';
import { SegmentedControl } from 'frontile/buttons';
import { Input, Switch } from 'frontile/forms';
import type PlannerService from 'wheelther/services/planner';
import type AtlasService from 'wheelther/services/atlas';
import type { RainMetric, TempMetric } from 'wheelther/services/planner';
import type { RainThreshold } from 'wheelther/utils/climate';
import { MONTHS, tempColor } from 'wheelther/utils/climate';
import {
  css,
  fmtDate,
  fmtKm,
  fmtPct,
  fmtShortDate,
  fmtTemp,
} from 'wheelther/utils/format';
import { gpxName, parseGpx, toGpx } from 'wheelther/utils/route';
import type { TripDay } from 'wheelther/utils/itinerary';

const eq = (a: unknown, b: unknown) => a === b;

export default class SidePanel extends Component<{ Element: HTMLElement }> {
  @service declare planner: PlannerService;
  @service declare atlas: AtlasService;

  @tracked drawnName = '';
  @tracked importError?: string;

  months = MONTHS.map((label, i) => ({ label, i }));

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
      coldest: t.coldestNight
        ? `${fmtTemp(t.coldestNight.nightLow)} on ${fmtShortDate(t.coldestNight.date)}${
            t.coldestNight.sleepTown ? ` near ${t.coldestNight.sleepTown}` : ''
          }`
        : '–',
      rainy: Math.round(t.rainyDays),
      rainyPct: fmtPct(t.rainyDays / (t.ridingDays || 1)),
    };
  }

  get dayRows() {
    return (this.trip?.days ?? []).map((d) => ({
      d,
      date: fmtShortDate(d.date),
      weekday: d.date.toLocaleDateString(undefined, { weekday: 'short' }),
      km: d.isRest ? 'rest' : `${Math.round(d.distance)}`,
      high: fmtTemp(d.weather.high),
      low: fmtTemp(d.nightLow),
      rain: fmtPct(d.weather.rainChance),
      color: Number.isNaN(d.weather.high)
        ? 'transparent'
        : tempColor(d.weather.high),
      isActive: d.n === this.planner.highlightedDay,
    }));
  }

  get cannotSave() {
    return this.planner.drawn.length < 2;
  }

  setMonth = (i: number) => this.planner.set('month', i);
  setTempMetric = (v: TempMetric) => this.planner.set('tempMetric', v);
  setRainMetric = (v: RainMetric) => this.planner.set('rainMetric', v);
  setRainThreshold = (v: RainThreshold) => this.planner.set('rainThreshold', v);
  toggle = (key: 'showTemp' | 'showRain' | 'isReversed', value: boolean) => {
    this.planner.set(key, value);
    if (key === 'isReversed') this.planner.set('highlightedDay', undefined);
  };

  selectRoute = (e: Event) => {
    void this.planner.selectRoute((e.target as HTMLSelectElement).value);
  };

  deleteSelected = () => {
    this.planner.deleteRoute(this.planner.routeId);
  };

  setStart = (v: string) => {
    if (/^\d{4}-\d{2}-\d{2}$/.test(v)) this.planner.set('start', v);
  };

  setKmPerDay = (v: string) => {
    const n = Number(v);
    if (Number.isFinite(n) && n >= 5 && n <= 400)
      this.planner.set('kmPerDay', n);
  };

  setRideDays = (v: string) => {
    const n = Number(v);
    if (Number.isInteger(n) && n >= 1 && n <= 60)
      this.planner.set('rideDays', n);
  };

  setRestDays = (v: string) => {
    const n = Number(v);
    if (Number.isInteger(n) && n >= 0 && n <= 30)
      this.planner.set('restDays', n);
  };

  get pattern() {
    const { rideDays, restDays } = this.planner;
    if (restDays === 0) return 'Riding every day, no rest days.';
    const d = (n: number) => `${n} day${n === 1 ? '' : 's'}`;
    return `Ride ${d(rideDays)}, rest ${d(restDays)}, repeat.`;
  }

  selectDay = (d: TripDay) => {
    this.planner.set(
      'highlightedDay',
      this.planner.highlightedDay === d.n ? undefined : d.n,
    );
    this.planner.set('month', d.date.getMonth());
  };

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
      this.planner.addRoute(
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
      <header class="wt-brand px-5 pt-5 pb-4">
        <div class="flex items-baseline justify-between gap-3">
          <h1 class="wt-logo">Wheel<span>ther</span></h1>
          <LinkTo @route="help" class="wt-help-link">How it works</LinkTo>
        </div>
        <p class="wt-muted mt-1 text-sm">What the weather usually does along
          your bike route, day by day.</p>
      </header>

      <div class="flex min-h-0 flex-1 flex-col gap-6 overflow-y-auto px-5 pb-6">
        <section aria-labelledby="h-month" class="flex flex-col gap-3">
          <h2 id="h-month" class="wt-h2">Climate on the map</h2>
          <div class="wt-months" role="radiogroup" aria-label="Month">
            {{#each this.months as |m|}}
              <button
                type="button"
                role="radio"
                aria-checked={{if (eq m.i this.planner.month) "true" "false"}}
                class="wt-month {{if (eq m.i this.planner.month) 'is-active'}}"
                {{on "click" (fn this.setMonth m.i)}}
              >{{m.label}}</button>
            {{/each}}
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

        <section aria-labelledby="h-route" class="flex flex-col gap-3">
          <h2 id="h-route" class="wt-h2">Route</h2>
          <div class="flex flex-col gap-1.5">
            <label for="route-picker" class="sr-only">Route</label>
            <div class="wt-select">
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
                so far). Double-click or press Save to finish. Points are joined
                with straight lines.</p>
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
                  disabled={{this.cannotSave}}
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
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                class="wt-btn"
                {{on "click" this.startDrawing}}
              >Draw a route</button>
              <label class="wt-btn">
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
                class="wt-btn is-ghost"
                {{on "click" this.exportGpx}}
              >Export GPX</button>
            </div>
          {{/if}}
          {{#if this.importError}}
            <p class="wt-error text-sm" role="alert">{{this.importError}}</p>
          {{/if}}
          <Switch
            @label="Ride it the other way"
            @size="sm"
            @isSelected={{this.planner.isReversed}}
            @onChange={{fn this.toggle "isReversed"}}
          />
        </section>

        <section aria-labelledby="h-trip" class="flex flex-col gap-3">
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
                @onChange={{this.setKmPerDay}}
                min="5"
                max="400"
                step="5"
              />
            </div>
            <div>
              <Input
                @label="Ride days"
                @type="number"
                @size="sm"
                @value="{{this.planner.rideDays}}"
                @onChange={{this.setRideDays}}
                min="1"
                max="60"
              />
            </div>
            <div>
              <Input
                @label="Rest days"
                @type="number"
                @size="sm"
                @value="{{this.planner.restDays}}"
                @onChange={{this.setRestDays}}
                min="0"
                max="30"
              />
            </div>
            <p class="wt-muted col-span-3 text-xs">{{this.pattern}}</p>
          </div>

          {{#if this.summary}}
            <dl class="wt-summary">
              <div><dt>Days</dt><dd>{{this.summary.days}}</dd><dd
                  class="wt-muted text-xs"
                >{{this.summary.riding}}
                  riding,
                  {{this.summary.rest}}
                  rest</dd></div>
              <div><dt>Arrive</dt><dd>{{this.summary.end}}</dd></div>
              <div><dt>Average high</dt><dd>{{this.summary.avgHigh}}</dd><dd
                  class="wt-muted text-xs"
                >on riding days</dd></div>
              <div><dt>Rainy riding days</dt><dd>{{this.summary.rainy}}</dd><dd
                  class="wt-muted text-xs"
                >about {{this.summary.rainyPct}}</dd></div>
              <div class="col-span-2"><dt>Coldest night</dt><dd
                >{{this.summary.coldest}}</dd></div>
            </dl>
          {{/if}}
        </section>

        {{#if this.trip}}
          <section aria-labelledby="h-days" class="flex flex-col gap-2">
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
      </div>
    </aside>
  </template>
}
