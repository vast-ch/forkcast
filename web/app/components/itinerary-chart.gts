import Component from '@glimmer/component';
import { service } from '@ember/service';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { modifier } from 'ember-modifier';
import type PlannerService from 'forkcast/services/planner';
import type { Ride } from 'forkcast/services/planner';
import type { Trip, TripDay } from 'forkcast/utils/itinerary';
import { tempSwatch, usualRange } from 'forkcast/utils/climate';
import { rainEmojiTier } from 'forkcast/utils/layers';
import TempPill from 'forkcast/components/temp-pill';
import {
  css,
  fmtDate,
  fmtDaylight,
  fmtDayTitle,
  fmtRideWind,
  fmtHours,
  fmtKm,
  fmtMm,
  fmtMonth,
  fmtPct,
  fmtTemp,
  fmtUsual,
} from 'forkcast/utils/format';
import { focusRing, inlineStats, title } from 'forkcast/utils/classes';

const COL = 18; // px per day
const NUM_Y = 10; // baseline of the day numbers
const LIGHTS_Y = 22; // baseline of the 🔦 marks under them
const RAIN_EMOJI_Y = 35; // baseline of the rain emoji under those
const LEFT = 42; // room for the axis labels (-10°C)

/**
 * Where one route's rows lie, top to bottom: its temperature band, then its
 * rain band. A route alone gets the full chart, with the 🔦 and rain emoji
 * rows over it; compared routes get a compact band each, under one row of day
 * numbers, on one temperature scale.
 */
interface Band {
  top: number;
  tempTop: number;
  tempH: number;
  rainTop: number;
  rainH: number;
  bottom: number;
  /** Degrees between the temperature lines */
  step: number;
}

/** A route alone: the bands under the three rows of day numbers and marks. */
const FULL: Band = {
  top: 0,
  tempTop: 42,
  tempH: 110,
  // Room for the rain band's caption above it.
  rainTop: 42 + 110 + 22,
  rainH: 34,
  bottom: 42 + 110 + 22 + 34 + 4,
  step: 5,
};

/** Compared routes: the day numbers' row, then a band per route. */
const HEAD = 16;
const COMPACT_H = 88;
const compactBand = (i: number): Band => {
  const top = HEAD + i * COMPACT_H;
  return {
    top,
    tempTop: top + 6,
    tempH: 56,
    rainTop: top + 66,
    rainH: 14,
    bottom: top + COMPACT_H,
    step: 10,
  };
};

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

/** A day's column: what picks it, across every route's band. */
interface Column {
  day: TripDay;
  x: number;
  isHighlighted: boolean;
  /** Set on the first day of a month after the trip's first: its name, for the line before it */
  monthStart?: string;
}

interface Bar {
  day: TripDay;
  x: number;
  barX: number;
  /** The bar's middle, where the usual-range line runs */
  midX: number;
  yHigh: number;
  barH: number;
  /** The thin line through the bar: from the usual highest high to the usual lowest low (8 in 10), if known */
  usualY?: number;
  usualEnd?: number;
  rainY: number;
  color: string;
  rainH: number;
  /** The map's rain emoji for the day's rainy days a week, if any */
  rainEmoji?: string;
  isHighlighted: boolean;
}

/** One route's band: its bars, its scale's lines and where it ends. */
interface Row {
  key: string;
  label: string;
  color: string;
  band: Band;
  bars: Bar[];
  gridLines: { label: string; y: number; isZero: boolean }[];
  /** The 🏁 after its last day, when another route goes on longer */
  end?: { x: number; y: number };
}

/** A day's usual extremes, 8 days in 10: the warmest high and coldest low (NaN if unknown). */
function usual(day: TripDay): [number, number] {
  return [
    usualRange(day.weather.high, day.weather.highSpread)[1],
    usualRange(day.nightLow, day.nightLowSpread)[0],
  ];
}

/** What a compared route does on a day: its stretch, a rest day, or arrived. */
function riding(d: TripDay | undefined): string {
  if (!d) return 'Arrived';
  if (d.isRest) return 'Rest day';
  const climb = d.climb !== null ? ` · ${Math.round(d.climb)}m up` : '';
  return `${fmtKm(d.distance)}${climb}`;
}

export default class ItineraryChart extends Component<{
  Args: { rows: { ride: Ride; trip: Trip }[] };
  Element: HTMLDivElement;
}> {
  @service declare planner: PlannerService;

  get isComparing() {
    return this.args.rows.length > 1;
  }

  /** The days of the longest trip: any route's day n is in column n. */
  get days(): TripDay[] {
    let days: TripDay[] = [];
    for (const { trip } of this.args.rows)
      if (trip.days.length > days.length) days = trip.days;
    return days;
  }

  /** One temperature scale for every route, so their bars compare. */
  get range(): [number, number] {
    let lo = Infinity;
    let hi = -Infinity;
    for (const { trip } of this.args.rows) {
      for (const d of trip.days) {
        if (Number.isNaN(d.weather.high)) continue;
        const [warm, cold] = usual(d);
        lo = Math.min(lo, d.weather.low, d.nightLow);
        hi = Math.max(hi, d.weather.high);
        if (!Number.isNaN(cold)) lo = Math.min(lo, cold);
        if (!Number.isNaN(warm)) hi = Math.max(hi, warm);
      }
    }
    if (!Number.isFinite(lo)) return [0, 20];
    return [Math.floor(lo / 5) * 5, Math.ceil(hi / 5) * 5];
  }

  y = (band: Band, t: number) => {
    const [lo, hi] = this.range;
    return band.tempTop + ((hi - t) / (hi - lo || 1)) * band.tempH;
  };

  get bands(): Band[] {
    return this.isComparing
      ? this.args.rows.map((_, i) => compactBand(i))
      : [FULL];
  }

  get width() {
    return colX(this.days.length + 2) + 8;
  }

  /** The selected column: a day, or a parking column when the map's week is
   * outside the trip. */
  get column(): number | undefined {
    const off = this.planner.offTrip;
    if (off) return off === 'before' ? 0 : this.days.length + 1;
    return this.planner.highlightedDay || undefined;
  }

  /** The parking columns at both ends, for a week before or after the trip. */
  get parking() {
    const y = this.height / 2;
    return (['before', 'after'] as const).map((side) => {
      const x = colX(side === 'before' ? 0 : this.days.length + 1);
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
    const first = fmtDate(this.days[0]!.date);
    const last = fmtDate(this.days[this.days.length - 1]!.date);
    if (this.isComparing)
      return off === 'before'
        ? `Before your trips, which start on ${first}`
        : `After your trips: the longest ends on ${last}`;
    return off === 'before'
      ? `Before your trip, which starts on ${first}`
      : `After your trip, which ends on ${last}`;
  }

  get height() {
    return this.bands[this.bands.length - 1]!.bottom;
  }

  /** Month names start at the foot of the first temperature band and read upwards. */
  get months() {
    const band = this.bands[0]!;
    const y = band.tempTop + band.tempH;
    return this.columns
      .filter((c) => c.monthStart)
      .map((c) => ({
        name: c.monthStart,
        x: c.x,
        y,
        transform: upright(c.x, y),
      }));
  }

  get columns(): Column[] {
    return this.days.map((day, i) => {
      const prev = this.days[i - 1];
      return {
        day,
        x: colX(day.n),
        isHighlighted: this.planner.highlightedDay === day.n,
        monthStart:
          prev !== undefined && prev.date.getMonth() !== day.date.getMonth()
            ? fmtMonth(day.date)
            : undefined,
      };
    });
  }

  /** Horizontal lines with their axis labels: every 5° (10° when compact)
   * and the rain band's 0–100%. */
  gridLines(band: Band) {
    const [lo, hi] = this.range;
    const out = [];
    for (
      let t = Math.ceil(lo / band.step) * band.step;
      t <= hi;
      t += band.step
    ) {
      out.push({ label: `${t}°C`, y: this.y(band, t), isZero: t === 0 });
    }
    const rain = this.isComparing ? [1, 0] : [1, 0.5, 0];
    for (const f of rain) {
      const y = band.rainTop + band.rainH * (1 - f);
      out.push({
        label: this.isComparing ? (f ? '' : 'rain') : `${f * 100}%`,
        y,
        isZero: false,
      });
    }
    return out;
  }

  get rows(): Row[] {
    const last = this.days.length;
    return this.args.rows.map(({ ride, trip }, i) => {
      const band = this.bands[i]!;
      const ends = trip.days.length;
      return {
        key: ride.key,
        label: ride.label,
        color: ride.color,
        band,
        gridLines: this.gridLines(band),
        bars: trip.days.map((day) => this.bar(band, day)),
        end:
          ends < last
            ? { x: colX(ends + 1) + COL / 2, y: band.tempTop + band.tempH / 2 }
            : undefined,
      };
    });
  }

  bar(band: Band, day: TripDay): Bar {
    const noData = Number.isNaN(day.weather.high);
    const high = noData ? 0 : day.weather.high;
    const low = noData ? 0 : Math.min(day.weather.low, day.nightLow);
    const rainH = noData ? 0 : day.weather.rainChance * band.rainH;
    const [warm, cold] = usual(day);
    const range =
      noData || Number.isNaN(warm) || Number.isNaN(cold)
        ? {}
        : { usualY: this.y(band, warm), usualEnd: this.y(band, cold) };
    // The day's chance as rainy days a week, so it reads like the map.
    const tier = noData
      ? undefined
      : rainEmojiTier(day.weather.rainChance * 7, this.planner.rainThreshold);
    return {
      ...range,
      day,
      x: colX(day.n),
      barX: colX(day.n) + 3,
      midX: colX(day.n) + 3 + this.barW / 2,
      yHigh: this.y(band, high),
      barH: Math.max(2, this.y(band, low) - this.y(band, high)),
      rainY: band.rainTop + band.rainH - rainH,
      color: tempSwatch(day.weather.high, 'var(--color-wt-muted)'),
      rainH,
      rainEmoji: tier?.emoji,
      isHighlighted: this.planner.highlightedDay === day.n,
    };
  }

  /** The selected day, of the longest trip (the same date on every route). */
  get selectedDay() {
    const n = this.planner.highlightedDay;
    return this.days.find((d) => d.n === n);
  }

  /** The selected day of the one route shown. */
  get detail() {
    if (this.isComparing) return undefined;
    return this.selectedDay;
  }

  get detailTitle() {
    return this.selectedDay ? fmtDayTitle(this.selectedDay) : '';
  }

  get detailRoute() {
    const d = this.detail;
    if (!d) return '';
    if (d.isRest) return 'Rest day';
    return `${fmtKm(d.distance)} · km ${Math.round(d.fromKm)}–${Math.round(d.toKm)}${
      d.climb !== null ? ` · ${Math.round(d.climb)}m climbing` : ''
    } · ${fmtHours(d.ridingHours)} riding${d.needsLights ? ' · 🔦 needs lights' : ''}`;
  }

  /** While comparing: the selected day on each route, side by side. */
  get comparison() {
    const n = this.planner.highlightedDay;
    if (!this.isComparing || !this.selectedDay) return [];
    return this.args.rows.map(({ ride, trip }) => {
      const day = trip.days.find((d) => d.n === n);
      return {
        key: ride.key,
        label: ride.label,
        swatch: css('background: ', ride.color),
        riding: riding(day),
        day,
      };
    });
  }

  select = (day: TripDay) => this.planner.toggleDay(day);

  /** A column's background: the selected day, else a rest day's shading, else
   * a tint on hover. */
  hitClass = (c: Column) =>
    c.isHighlighted
      ? 'fill-wt-pick-wash'
      : c.day.isRest
        ? 'fill-wt-ink/4'
        : 'fill-transparent group-hover:fill-wt-accent/8';

  /** What a screen reader says for the selected day. */
  get valueText() {
    const d = this.detail;
    if (this.offTripNote)
      return `${this.planner.weekSlot.label}: ${this.offTripNote}`;
    if (this.comparison.length) {
      const each = this.comparison.map(({ label, riding, day }) =>
        day
          ? `${label}: ${riding}, low ${fmtTemp(day.nightLow)}, high ${fmtTemp(day.weather.high)}, rain chance ${fmtPct(day.weather.rainChance)}`
          : `${label}: ${riding}`,
      );
      return `${this.detailTitle}; ${each.join('; ')}`;
    }
    if (!d) return 'No day selected';
    const w = d.weather;
    return `${this.detailTitle}, ${this.detailRoute}, low ${fmtTemp(d.nightLow)} ${fmtUsual(d.nightLow, d.nightLowSpread)}, high ${fmtTemp(w.high)} ${fmtUsual(w.high, w.highSpread)}, rain chance ${fmtPct(w.rainChance)}, wind ${fmtRideWind(w.windSpeed, d.windPush)}, daylight ${fmtDaylight(d.daylight)}`;
  }

  /** Arrow keys step through the days (Home and End jump to the ends). */
  onKey = (e: KeyboardEvent) => {
    const days = this.days;
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
  numY = NUM_Y;
  lightsY = LIGHTS_Y;
  rainEmojiY = RAIN_EMOJI_Y;
  /** Right edge of the axis labels. */
  axisX = LEFT - 6;
  firstDayX = colX(1);
  rainCaptionY = FULL.rainTop;
  bandHeight = (b: Band) => b.rainTop + b.rainH - b.tempTop;

  <template>
    <div class="flex min-h-0 flex-col gap-2" ...attributes>
      <div
        class="flex min-h-[2.75rem] flex-wrap items-baseline justify-between gap-x-4 gap-y-1"
        aria-hidden="true"
      >
        {{#if this.detail}}
          <div class="min-w-0">
            <p class={{title}}>{{this.detailTitle}}</p>
            <p class="text-xs text-wt-muted">{{this.detailRoute}}</p>
          </div>
          <dl class={{inlineStats}}>
            <div><dt>Low</dt><dd><TempPill @t={{this.detail.nightLow}} />
                <span class="text-xs text-wt-muted">{{fmtUsual
                    this.detail.nightLow
                    this.detail.nightLowSpread
                  }}</span></dd></div>
            <div><dt>High</dt><dd><TempPill @t={{this.detail.weather.high}} />
                <span class="text-xs text-wt-muted">{{fmtUsual
                    this.detail.weather.high
                    this.detail.weather.highSpread
                  }}</span></dd></div>
            <div><dt>Rain chance</dt><dd>{{fmtPct
                  this.detail.weather.rainChance
                }}</dd></div>
            <div><dt>When it rains</dt><dd>{{fmtMm
                  this.detail.weather.wetDayMm
                }}</dd></div>
            {{#unless this.detail.isRest}}
              <div><dt>Wind</dt><dd>{{fmtRideWind
                    this.detail.weather.windSpeed
                    this.detail.windPush
                  }}</dd></div>
            {{/unless}}
            <div><dt>Daylight</dt><dd>{{fmtDaylight
                  this.detail.daylight
                }}</dd></div>
          </dl>
        {{else if this.comparison.length}}
          {{! The selected day on each route, a row each, in the chart's order. }}
          <div class="min-w-0 flex-1">
            <p class={{title}}>{{this.detailTitle}}</p>
            <div class="overflow-x-auto">
              <table
                class="wt-compare mt-1 w-full text-[0.8rem] [&_td]:py-0.5 [&_td]:pr-3 [&_td]:align-middle [&_th]:pr-3 [&_th]:text-left [&_th]:font-normal [&_th]:text-wt-muted"
              >
                <thead>
                  <tr><th>Route</th><th>Riding</th><th>Low</th><th>High</th><th
                    >Rain chance</th><th>Wind</th></tr>
                </thead>
                <tbody>
                  {{#each this.comparison key="key" as |c|}}
                    <tr>
                      <td class="max-w-[16rem] max-desktop:max-w-[7rem]">
                        <span class="flex items-center gap-1.5"><span
                            class="h-3 w-[0.35rem] flex-none rounded-xs"
                            style={{c.swatch}}
                          ></span><span
                            class="truncate"
                          >{{c.label}}</span></span>
                      </td>
                      <td class="font-data whitespace-nowrap">{{c.riding}}</td>
                      {{#if c.day}}
                        <td><TempPill @t={{c.day.nightLow}} /></td>
                        <td><TempPill @t={{c.day.weather.high}} /></td>
                        <td class="font-data">{{fmtPct
                            c.day.weather.rainChance
                          }}</td>
                        <td class="font-data whitespace-nowrap">{{#if
                            c.day.isRest
                          }}–{{else}}{{fmtRideWind
                              c.day.weather.windSpeed
                              c.day.windPush
                            }}{{/if}}</td>
                      {{else}}
                        <td></td><td></td><td></td><td></td>
                      {{/if}}
                    </tr>
                  {{/each}}
                </tbody>
              </table>
            </div>
          </div>
        {{else if this.offTripNote}}
          <div class="min-w-0">
            <p class={{title}}>{{this.planner.weekSlot.label}}</p>
            <p class="text-xs text-wt-muted">{{this.offTripNote}}</p>
          </div>
        {{/if}}
      </div>
      {{! The chart is the way to pick a day: click a column, or focus it and
          step through the days with the arrow keys. While comparing, a band
          per route under one row of day numbers, scrolling together. }}
      {{! A slider's content is presentational by definition; the drawing is
          aria-hidden and the selected day is read out as the value. }}
      {{! template-lint-disable require-presentational-children }}
      <div
        class="overflow-x-auto overflow-y-hidden [scrollbar-width:thin]
          {{focusRing}}"
        role="slider"
        tabindex="0"
        aria-label="Day of the trip (temperatures and rain for each day)"
        aria-valuemin="1"
        aria-valuemax={{this.days.length}}
        aria-valuenow={{if
          this.planner.highlightedDay
          this.planner.highlightedDay
        }}
        aria-valuetext={{this.valueText}}
        {{on "keydown" this.onKey}}
        {{scrollToColumn this.column}}
      >
        <svg
          width={{this.width}}
          height={{this.height}}
          aria-hidden="true"
          class="fill-wt-muted font-data text-[9px]"
        >
          {{! Its labels are small and muted, in the data font, unless they say
              otherwise. }}
          {{#each this.rows as |r|}}
            {{#each r.gridLines as |g|}}
              <line
                x1={{this.left}}
                x2={{this.width}}
                y1={{g.y}}
                y2={{g.y}}
                class={{if
                  g.isZero
                  "stroke-wt-rule [stroke-dasharray:3_3]"
                  "stroke-wt-line"
                }}
              />
              <text
                x={{this.axisX}}
                y={{g.y}}
                dy="3.5"
                text-anchor="end"
                class="text-[10px]"
              >{{g.label}}</text>
            {{/each}}
            {{#if this.isComparing}}
              {{! The route's colour down the left edge, as on the map. }}
              <rect
                class="wt-band"
                x="0"
                y={{r.band.tempTop}}
                width="4"
                height={{this.bandHeight r.band}}
                rx="2"
                style={{css "fill: " r.color}}
              />
            {{/if}}
          {{/each}}
          {{#unless this.isComparing}}
            <text
              x={{this.firstDayX}}
              y={{this.rainCaptionY}}
              dy="-5"
              class="font-body text-[11px]"
            >Chance of a rainy day (over
              {{this.planner.rainThreshold}}mm)</text>
          {{/unless}}
          {{! The parking columns at both ends: where the map's week is when it
              lies before or after the trip. }}
          {{#each this.parking as |p|}}
            <g>
              <rect
                x={{p.x}}
                y="0"
                width={{this.colW}}
                height={{this.height}}
                class="[stroke-dasharray:3_3]
                  {{if
                    p.isActive
                    'fill-wt-pick-wash stroke-wt-pick'
                    'fill-transparent stroke-wt-line'
                  }}"
              />
              <text
                x={{p.cx}}
                y={{p.y}}
                transform={{p.transform}}
                text-anchor="middle"
                dominant-baseline="central"
                class={{if p.isActive "fill-wt-pick font-semibold"}}
              >{{p.label}}</text>
            </g>
          {{/each}}
          {{#each this.columns as |c|}}
            {{! Clicking a column picks its day on every route; keyboards use
                the slider above. }}
            {{! template-lint-disable no-invalid-interactive }}
            <g
              class="group cursor-pointer"
              aria-hidden="true"
              {{on "click" (fn this.select c.day)}}
            >
              <rect
                x={{c.x}}
                y="0"
                width={{this.colW}}
                height={{this.height}}
                class={{this.hitClass c}}
              />
              {{#if c.monthStart}}
                <line
                  x1={{c.x}}
                  x2={{c.x}}
                  y1="4"
                  y2={{this.height}}
                  class="stroke-wt-rule"
                />
              {{/if}}
              <text
                x={{c.x}}
                dx={{this.half}}
                y={{this.numY}}
                text-anchor="middle"
                class={{if c.isHighlighted "fill-wt-pick font-semibold"}}
              >{{c.day.n}}</text>
            </g>
          {{/each}}
          {{! Each route's bars over the columns; clicks go through to them. }}
          {{#each this.rows key="key" as |r|}}
            <g class="pointer-events-none">
              {{#each r.bars as |b|}}
                {{#unless this.isComparing}}
                  {{#if b.day.needsLights}}
                    <text
                      x={{b.x}}
                      dx={{this.half}}
                      y={{this.lightsY}}
                      text-anchor="middle"
                      class="text-[10px]"
                    >🔦</text>
                  {{/if}}
                  {{! In the body font: the data font's fallback draws ☔ as a
                      plain glyph. }}
                  {{#if b.rainEmoji}}
                    <text
                      x={{b.x}}
                      dx={{this.half}}
                      y={{this.rainEmojiY}}
                      text-anchor="middle"
                      class="wt-rain-emoji font-body text-[11px]"
                    >{{b.rainEmoji}}</text>
                  {{/if}}
                {{/unless}}
                {{#if b.usualEnd}}
                  <line
                    x1={{b.midX}}
                    x2={{b.midX}}
                    y1={{b.usualY}}
                    y2={{b.usualEnd}}
                    class="stroke-wt-muted stroke-1"
                  />
                {{/if}}
                <rect
                  x={{b.barX}}
                  y={{b.yHigh}}
                  width={{this.barW}}
                  height={{b.barH}}
                  class={{if
                    b.isHighlighted
                    "stroke-wt-pick stroke-2"
                    "stroke-black/18 stroke-[0.5]"
                  }}
                  style={{css "fill: " b.color}}
                  rx="2"
                />
                <rect
                  x={{b.barX}}
                  y={{b.rainY}}
                  width={{this.barW}}
                  height={{b.rainH}}
                  class="fill-wt-rain opacity-75"
                  rx="1"
                />
              {{/each}}
              {{#if r.end}}
                <text
                  class="wt-arrived font-body text-[11px]"
                  x={{r.end.x}}
                  y={{r.end.y}}
                  text-anchor="middle"
                  dominant-baseline="central"
                >🏁</text>
              {{/if}}
            </g>
          {{/each}}
          {{! On top of every column, so the next day's bar can't cover them;
              the halo keeps them readable over the bars. }}
          {{#each this.months as |m|}}
            <text
              x={{m.x}}
              y={{m.y}}
              transform={{m.transform}}
              dominant-baseline="central"
              class="pointer-events-none stroke-wt-paper stroke-[3px] [paint-order:stroke]"
            >{{m.name}}</text>
          {{/each}}
        </svg>
      </div>
    </div>
  </template>
}
