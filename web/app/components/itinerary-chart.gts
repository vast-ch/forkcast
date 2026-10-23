import Component from '@glimmer/component';
import { service } from '@ember/service';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type PlannerService from 'forkcast/services/planner';
import type { Trip, TripDay } from 'forkcast/utils/itinerary';
import { tempSwatch } from 'forkcast/utils/climate';
import {
  css,
  fmtDayTitle,
  fmtKm,
  fmtMm,
  fmtPct,
  fmtShortDate,
  fmtTemp,
} from 'forkcast/utils/format';

const COL = 18; // px per day
const TOP = 14;
const TEMP_H = 110;
const GAP = 22; // room for the rain band's caption
const RAIN_H = 34;
const NUMS = 12; // row of day numbers under the rain band
const AXIS = 18;
const LEFT = 34;

interface Bar {
  day: TripDay;
  x: number;
  barX: number;
  yHigh: number;
  barH: number;
  rainY: number;
  color: string;
  rainH: number;
  label?: string;
  isHighlighted: boolean;
  monthStart: boolean;
}

export default class ItineraryChart extends Component<{
  Args: { trip: Trip };
  Element: HTMLDivElement;
}> {
  @service declare planner: PlannerService;

  get range(): [number, number] {
    let lo = Infinity;
    let hi = -Infinity;
    for (const d of this.args.trip.days) {
      if (Number.isNaN(d.weather.high)) continue;
      lo = Math.min(lo, d.weather.low, d.nightLow);
      hi = Math.max(hi, d.weather.high);
    }
    if (!Number.isFinite(lo)) return [0, 20];
    return [Math.floor(lo / 5) * 5, Math.ceil(hi / 5) * 5];
  }

  y = (t: number) => {
    const [lo, hi] = this.range;
    return TOP + ((hi - t) / (hi - lo || 1)) * TEMP_H;
  };

  get width() {
    return LEFT + this.args.trip.days.length * COL + 8;
  }

  get height() {
    return TOP + TEMP_H + GAP + RAIN_H + NUMS + AXIS;
  }

  get rainTop() {
    return TOP + TEMP_H + GAP;
  }

  get rainTicks() {
    return [1, 0.5, 0].map((f) => ({
      label: `${f * 100}%`,
      y: this.rainTop + RAIN_H * (1 - f),
    }));
  }

  get numY() {
    return this.rainTop + RAIN_H + 10;
  }

  get axisY() {
    return this.rainTop + RAIN_H + NUMS + 13;
  }

  get gridLines() {
    const [lo, hi] = this.range;
    const out = [];
    for (let t = lo; t <= hi; t += 5) {
      out.push({ t, y: this.y(t), isZero: t === 0 });
    }
    return out;
  }

  get bars(): Bar[] {
    return this.args.trip.days.map((day, i) => {
      const noData = Number.isNaN(day.weather.high);
      const high = noData ? 0 : day.weather.high;
      const low = noData ? 0 : Math.min(day.weather.low, day.nightLow);
      const prev = this.args.trip.days[i - 1];
      const rainH = noData ? 0 : day.weather.rainChance * RAIN_H;
      return {
        day,
        x: LEFT + i * COL,
        barX: LEFT + i * COL + 3,
        yHigh: this.y(high),
        barH: Math.max(2, this.y(low) - this.y(high)),
        rainY: this.rainTop + RAIN_H - rainH,
        color: tempSwatch(day.weather.high, 'var(--wt-muted)'),
        rainH,
        label:
          i === 0 ||
          day.date.getDate() === 1 ||
          (day.n % 7 === 1 && day.n > 1 && !this.nearMonthStart(i))
            ? fmtShortDate(day.date)
            : undefined,
        isHighlighted: this.planner.highlightedDay === day.n,
        monthStart:
          i > 0 &&
          prev !== undefined &&
          prev.date.getMonth() !== day.date.getMonth(),
      };
    });
  }

  /** Is a 1 of the month within three days of day index `i`? Its label wins,
   * so a weekly label next to it would overlap. */
  nearMonthStart(i: number): boolean {
    const days = this.args.trip.days;
    for (
      let k = Math.max(0, i - 3);
      k <= Math.min(days.length - 1, i + 3);
      k++
    ) {
      if (k !== i && days[k]!.date.getDate() === 1) return true;
    }
    return false;
  }

  get detail() {
    const n = this.planner.highlightedDay;
    return this.args.trip.days.find((d) => d.n === n);
  }

  get detailTitle() {
    return this.detail ? fmtDayTitle(this.detail) : '';
  }

  get detailRoute() {
    const d = this.detail;
    if (!d) return '';
    if (d.isRest) return 'Rest day';
    return `${fmtKm(d.distance)} · km ${Math.round(d.fromKm)}–${Math.round(d.toKm)}${
      d.climb !== null ? ` · ${Math.round(d.climb)} m climbing` : ''
    }`;
  }

  select = (day: TripDay) => this.planner.toggleDay(day);

  /** What a screen reader says for the selected day. */
  get valueText() {
    const d = this.detail;
    if (!d) return 'No day selected';
    const w = d.weather;
    return `${this.detailTitle}, ${this.detailRoute}, high ${fmtTemp(w.high)}, night ${fmtTemp(d.nightLow)}, rain chance ${fmtPct(w.rainChance)}`;
  }

  /** Arrow keys step through the days (Home and End jump to the ends). */
  onKey = (e: KeyboardEvent) => {
    const days = this.args.trip.days;
    const now = this.planner.highlightedDay ?? 0;
    const n =
      e.key === 'ArrowRight' || e.key === 'ArrowUp'
        ? now + 1
        : e.key === 'ArrowLeft' || e.key === 'ArrowDown'
          ? now - 1
          : e.key === 'Home'
            ? 1
            : e.key === 'End'
              ? days.length
              : undefined;
    if (n === undefined) return;
    e.preventDefault();
    const day = days[Math.min(days.length, Math.max(1, n)) - 1];
    if (!day) return;
    this.planner.highlightDay(day);
    // Keep the day's column in view.
    const el = e.currentTarget as HTMLElement;
    const x = LEFT + (day.n - 1) * COL;
    if (x < el.scrollLeft + LEFT) el.scrollLeft = x - LEFT;
    else if (x + COL > el.scrollLeft + el.clientWidth)
      el.scrollLeft = x + COL - el.clientWidth + 8;
  };

  half = COL / 2;
  barW = COL - 6;
  colW = COL;
  left = LEFT;

  <template>
    <div class="flex min-h-0 flex-col gap-2" ...attributes>
      <div
        class="flex min-h-[2.75rem] flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
        aria-hidden="true"
      >
        {{#if this.detail}}
          <div class="min-w-0">
            <p class="wt-title">{{this.detailTitle}}</p>
            <p class="wt-muted text-xs">{{this.detailRoute}}</p>
          </div>
          <dl class="wt-inline-stats">
            <div><dt>High</dt><dd>{{fmtTemp
                  this.detail.weather.high
                }}</dd></div>
            <div><dt>Night</dt><dd>{{fmtTemp this.detail.nightLow}}</dd></div>
            <div><dt>Rain chance</dt><dd>{{fmtPct
                  this.detail.weather.rainChance
                }}</dd></div>
            <div><dt>Avg rain</dt><dd>{{fmtMm
                  this.detail.weather.rainMm
                }}</dd></div>
          </dl>
        {{/if}}
      </div>
      {{! The chart is the way to pick a day: click a column, or focus it and
          step through the days with the arrow keys. }}
      {{! A slider's content is presentational by definition; the drawing is
          aria-hidden and the selected day is read out as the value. }}
      {{! template-lint-disable require-presentational-children }}
      <div
        class="wt-scroll overflow-x-auto overflow-y-hidden"
        role="slider"
        tabindex="0"
        aria-label="Day of the trip (expected temperatures and rain for each day)"
        aria-valuemin="1"
        aria-valuemax={{@trip.days.length}}
        aria-valuenow={{this.planner.highlightedDay}}
        aria-valuetext={{this.valueText}}
        {{on "keydown" this.onKey}}
      >
        <svg
          width={{this.width}}
          height={{this.height}}
          aria-hidden="true"
          class="block"
        >
          {{#each this.gridLines as |g|}}
            <line
              x1={{this.left}}
              x2={{this.width}}
              y1={{g.y}}
              y2={{g.y}}
              class={{if g.isZero "wt-grid-zero" "wt-grid"}}
            />
            <text
              x="28"
              y={{g.y}}
              dy="3.5"
              text-anchor="end"
              class="wt-axis"
            >{{g.t}}°</text>
          {{/each}}
          <text
            x={{this.left}}
            y={{this.rainTop}}
            dy="-5"
            class="wt-axis wt-axis-title"
          >Chance of a rainy day (over {{this.planner.rainThreshold}} mm)</text>
          {{#each this.rainTicks as |tick|}}
            <line
              x1={{this.left}}
              x2={{this.width}}
              y1={{tick.y}}
              y2={{tick.y}}
              class="wt-grid"
            />
            <text
              x="28"
              y={{tick.y}}
              dy="3.5"
              text-anchor="end"
              class="wt-axis"
            >{{tick.label}}</text>
          {{/each}}
          {{#each this.bars as |b|}}
            {{! Clicking a column picks its day; keyboards use the slider above. }}
            {{! template-lint-disable no-invalid-interactive }}
            <g
              class="wt-day
                {{if b.isHighlighted 'is-active'}}
                {{if b.day.isRest 'is-rest'}}"
              aria-hidden="true"
              {{on "click" (fn this.select b.day)}}
            >
              <rect
                x={{b.x}}
                y="0"
                width={{this.colW}}
                height={{this.height}}
                class="wt-day-hit"
              />
              {{#if b.monthStart}}
                <line
                  x1={{b.x}}
                  x2={{b.x}}
                  y1="4"
                  y2={{this.height}}
                  class="wt-month-line"
                />
              {{/if}}
              {{#if b.day.isRest}}
                <text
                  x={{b.x}}
                  dx={{this.half}}
                  y="10"
                  text-anchor="middle"
                  class="wt-rest-label"
                >R</text>
              {{else}}
                <rect
                  x={{b.barX}}
                  y={{b.yHigh}}
                  width={{this.barW}}
                  height={{b.barH}}
                  class="wt-temp-bar"
                  style={{css "fill: " b.color}}
                  rx="2"
                />
                <rect
                  x={{b.barX}}
                  y={{b.rainY}}
                  width={{this.barW}}
                  height={{b.rainH}}
                  class="wt-rain-bar"
                  rx="1"
                />
              {{/if}}
              <text
                x={{b.x}}
                dx={{this.half}}
                y={{this.numY}}
                text-anchor="middle"
                class="wt-day-num"
              >{{b.day.n}}</text>
              {{#if b.label}}
                <text
                  x={{b.x}}
                  y={{this.axisY}}
                  class="wt-axis"
                >{{b.label}}</text>
              {{/if}}
            </g>
          {{/each}}
        </svg>
      </div>
    </div>
  </template>
}
