import Component from '@glimmer/component';
import { service } from '@ember/service';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import type PlannerService from 'forkcast/services/planner';
import type { Trip, TripDay } from 'forkcast/utils/itinerary';
import { tempColor } from 'forkcast/utils/climate';
import {
  css,
  fmtDate,
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
    return TOP + TEMP_H + GAP + RAIN_H + AXIS;
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

  get axisY() {
    return this.rainTop + RAIN_H + 13;
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
      return {
        day,
        x: LEFT + i * COL,
        barX: LEFT + i * COL + 3,
        yHigh: this.y(high),
        barH: Math.max(2, this.y(low) - this.y(high)),
        rainY:
          TOP +
          TEMP_H +
          GAP +
          RAIN_H -
          (noData ? 0 : day.weather.rainChance * RAIN_H),
        color: noData ? 'var(--wt-muted)' : tempColor(high),
        rainH: noData ? 0 : day.weather.rainChance * RAIN_H,
        label:
          i === 0 || day.date.getDate() === 1 || (day.n % 7 === 1 && day.n > 1)
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

  get detail() {
    const n = this.planner.highlightedDay;
    return this.args.trip.days.find((d) => d.n === n);
  }

  get detailTitle() {
    const d = this.detail;
    if (!d) return '';
    return `Day ${d.n} · ${fmtDate(d.date)}`;
  }

  get detailRoute() {
    const d = this.detail;
    if (!d) return '';
    if (d.isRest) return 'Rest day';
    return `${fmtKm(d.distance)} · km ${Math.round(d.fromKm)}–${Math.round(d.toKm)}${
      d.climb !== null ? ` · ${Math.round(d.climb)} m climbing` : ''
    }`;
  }

  select = (day: TripDay) => {
    this.planner.set(
      'highlightedDay',
      this.planner.highlightedDay === day.n ? undefined : day.n,
    );
    // Follow the trip with the map's climate month.
    this.planner.showDate(day.date);
  };

  fmtTemp = fmtTemp;
  fmtPct = fmtPct;
  fmtMm = fmtMm;
  half = COL / 2;
  barW = COL - 6;
  colW = COL;
  left = LEFT;

  <template>
    <div class="flex min-h-0 flex-col gap-2" ...attributes>
      <div
        class="flex min-h-[2.75rem] flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
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
      <div class="wt-scroll overflow-x-auto overflow-y-hidden">
        <svg
          width={{this.width}}
          height={{this.height}}
          role="img"
          aria-label="Expected temperatures and rain for each day of the trip"
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
            {{! Mouse shortcut only; the day table in the side panel is the accessible way to pick a day. }}
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
