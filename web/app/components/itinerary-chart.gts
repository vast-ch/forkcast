import Component from '@glimmer/component';
import { service } from '@ember/service';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import type PlannerService from 'forkcast/services/planner';
import type { Trip, TripDay } from 'forkcast/utils/itinerary';
import { tempSwatch } from 'forkcast/utils/climate';
import {
  css,
  fmtDate,
  fmtDayTitle,
  fmtKm,
  fmtMm,
  fmtMonth,
  fmtPct,
  fmtTemp,
} from 'forkcast/utils/format';

const COL = 18; // px per day
const TOP = 14; // room for the day numbers
const TEMP_H = 110;
const GAP = 22; // room for the rain band's caption
const RAIN_H = 34;
const BOTTOM = 4;
const LEFT = 34;

// Columns: 0 is the "before the trip" parking column, 1 … N are the days
// (day n in column n), N + 1 is "after the trip".

/** Left edge of column `c`. */
const colX = (c: number) => LEFT + c * COL;

/** SVG transform that turns text at (x, y) to read upwards. */
const upright = (x: number, y: number) => `rotate(-90 ${x} ${y})`;

/** Keeps the selected column in view however it was picked (chart, map, week slider). */
const scrollToColumn = modifier<{
  Element: HTMLElement;
  Args: { Positional: [number | undefined] };
}>((el, [c]) => {
  if (c === undefined) return;
  const x = colX(c);
  if (x < el.scrollLeft + LEFT) el.scrollLeft = x - LEFT;
  else if (x + COL > el.scrollLeft + el.clientWidth)
    el.scrollLeft = x + COL - el.clientWidth + 8;
});

/** The day a key moves to from day `now` (1-based) of `last`. */
const KEY_STEPS: Record<string, (now: number, last: number) => number> = {
  ArrowRight: (now) => now + 1,
  ArrowUp: (now) => now + 1,
  ArrowLeft: (now) => now - 1,
  ArrowDown: (now) => now - 1,
  Home: () => 1,
  End: (_, last) => last,
};

interface Bar {
  day: TripDay;
  x: number;
  barX: number;
  yHigh: number;
  barH: number;
  rainY: number;
  color: string;
  rainH: number;
  isHighlighted: boolean;
  /** Set on the first day of a month after the trip's first: its name, for the line before it */
  monthStart?: string;
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
    return colX(this.args.trip.days.length + 2) + 8;
  }

  /** The selected column: a day, or a parking column when the map's week is
   * outside the trip. */
  get column(): number | undefined {
    const off = this.planner.offTrip;
    if (off) return off === 'before' ? 0 : this.args.trip.days.length + 1;
    return this.planner.highlightedDay;
  }

  /** The parking columns at both ends, for a week before or after the trip. */
  get parking() {
    const y = TOP + TEMP_H / 2;
    return (['before', 'after'] as const).map((side) => {
      const x = colX(side === 'before' ? 0 : this.args.trip.days.length + 1);
      const cx = x + COL / 2;
      return {
        x,
        cx,
        y,
        label: side === 'before' ? 'Before' : 'After',
        transform: upright(cx, y),
        isActive: this.planner.offTrip === side,
      };
    });
  }

  /** Shown above the chart when the map's week is outside the trip. */
  get offTripNote() {
    const off = this.planner.offTrip;
    if (!off) return '';
    const days = this.args.trip.days;
    return off === 'before'
      ? `Before your trip, which starts on ${fmtDate(days[0]!.date)}`
      : `After your trip, which ends on ${fmtDate(days[days.length - 1]!.date)}`;
  }

  get height() {
    return TOP + TEMP_H + GAP + RAIN_H + BOTTOM;
  }

  get rainTop() {
    return TOP + TEMP_H + GAP;
  }

  /** Month names start at the foot of the temperature band and read upwards. */
  get months() {
    const y = TOP + TEMP_H;
    return this.bars
      .filter((b) => b.monthStart)
      .map((b) => ({
        name: b.monthStart,
        x: b.x,
        y,
        transform: upright(b.x, y),
      }));
  }

  /** Horizontal lines with their axis labels: every 5° and the rain band's 0–100%. */
  get gridLines() {
    const [lo, hi] = this.range;
    const out = [];
    for (let t = lo; t <= hi; t += 5) {
      out.push({ label: `${t}°`, y: this.y(t), isZero: t === 0 });
    }
    for (const f of [1, 0.5, 0]) {
      const y = this.rainTop + RAIN_H * (1 - f);
      out.push({ label: `${f * 100}%`, y, isZero: false });
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
        x: colX(day.n),
        barX: colX(day.n) + 3,
        yHigh: this.y(high),
        barH: Math.max(2, this.y(low) - this.y(high)),
        rainY: this.rainTop + RAIN_H - rainH,
        color: tempSwatch(day.weather.high, 'var(--wt-muted)'),
        rainH,
        isHighlighted: this.planner.highlightedDay === day.n,
        monthStart:
          prev !== undefined && prev.date.getMonth() !== day.date.getMonth()
            ? fmtMonth(day.date)
            : undefined,
      };
    });
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
    if (this.offTripNote)
      return `${this.planner.weekSlot.label}: ${this.offTripNote}`;
    if (!d) return 'No day selected';
    const w = d.weather;
    return `${this.detailTitle}, ${this.detailRoute}, high ${fmtTemp(w.high)}, night ${fmtTemp(d.nightLow)}, rain chance ${fmtPct(w.rainChance)}`;
  }

  /** Arrow keys step through the days (Home and End jump to the ends). */
  onKey = (e: KeyboardEvent) => {
    const days = this.args.trip.days;
    const step = KEY_STEPS[e.key];
    if (!step) return;
    e.preventDefault();
    // From a parking column, the first step goes to the nearest day.
    const n = step(this.column ?? 0, days.length);
    const day = days[Math.min(days.length, Math.max(1, n)) - 1];
    if (day) this.planner.highlightDay(day);
  };

  half = COL / 2;
  barW = COL - 6;
  colW = COL;
  left = LEFT;
  firstDayX = colX(1);

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
        {{else if this.offTripNote}}
          <div class="min-w-0">
            <p class="wt-title">{{this.planner.weekSlot.label}}</p>
            <p class="wt-muted text-xs">{{this.offTripNote}}</p>
          </div>
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
        {{scrollToColumn this.column}}
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
            >{{g.label}}</text>
          {{/each}}
          <text
            x={{this.firstDayX}}
            y={{this.rainTop}}
            dy="-5"
            class="wt-axis wt-axis-title"
          >Chance of a rainy day (over {{this.planner.rainThreshold}} mm)</text>
          {{#each this.parking as |p|}}
            <g class="wt-park {{if p.isActive 'is-active'}}">
              <rect
                x={{p.x}}
                y="0"
                width={{this.colW}}
                height={{this.height}}
                class="wt-park-slot"
              />
              <text
                x={{p.cx}}
                y={{p.y}}
                transform={{p.transform}}
                text-anchor="middle"
                dominant-baseline="central"
                class="wt-park-label"
              >{{p.label}}</text>
            </g>
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
              <text
                x={{b.x}}
                dx={{this.half}}
                y="10"
                text-anchor="middle"
                class="wt-day-num"
              >{{b.day.n}}</text>
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
            </g>
          {{/each}}
          {{! On top of every column, so the next day's bar can't cover them. }}
          {{#each this.months as |m|}}
            <text
              x={{m.x}}
              y={{m.y}}
              transform={{m.transform}}
              dominant-baseline="central"
              class="wt-month-name"
            >{{m.name}}</text>
          {{/each}}
        </svg>
      </div>
    </div>
  </template>
}
