import Component from '@glimmer/component';
import { service } from '@ember/service';
import type PlannerService from 'forkcast/services/planner';
import TempPill from 'forkcast/components/temp-pill';
import { windSteadiness } from 'forkcast/utils/climate';
import { isMissing } from 'forkcast/utils/helpers';
import {
  fmtDaylight,
  fmtHours,
  fmtDayTitle,
  fmtKm,
  fmtMm,
  fmtPct,
  fmtUsual,
  fmtRideWind,
  fmtWind,
} from 'forkcast/utils/format';

const round = (n: number | null | undefined) =>
  isMissing(n) ? '–' : Math.round(n);

/** Readout of the climate under the pointer, and of the trip day when over the route. */
export default class HoverCard extends Component<{ Element: HTMLDivElement }> {
  @service declare planner: PlannerService;

  get hover() {
    return this.planner.hover;
  }

  get weekLabel() {
    return this.planner.weekSlot.label;
  }

  /** Expected rain over the week shown, in total. */
  get weekRain() {
    const c = this.hover?.climate;
    return c ? fmtMm(c.rainMm * this.planner.weekSlot.days) : '';
  }

  /** Expected rainy days in the week shown, e.g. "2.6". */
  get weekRainyDays() {
    const c = this.hover?.climate;
    if (!c || isMissing(c.rainChance)) return '–';
    return (c.rainChance * this.planner.weekSlot.days).toFixed(1);
  }

  get coords() {
    const h = this.hover;
    if (!h) return '';
    const ns = h.lat >= 0 ? 'N' : 'S';
    const ew = h.lon >= 0 ? 'E' : 'W';
    return `${Math.abs(h.lat).toFixed(2)}° ${ns}  ${Math.abs(h.lon).toFixed(2)}° ${ew}`;
  }

  get route() {
    return this.hover?.onRoute;
  }

  /** How much the high and low were shifted for the route's height, if noticeably. */
  get altitudeNote() {
    const w = this.route?.weather;
    const high = w?.highAltitudeShift ?? 0;
    const low = w?.lowAltitudeShift ?? 0;
    if (Math.abs(high) < 0.5 && Math.abs(low) < 0.5) return '';
    const fmt = (s: number) => {
      const r = Math.round(s * 10) / 10;
      return `${r > 0 ? '+' : r < 0 ? '−' : ''}${Math.abs(r).toFixed(1)}°C`;
    };
    return `high ${fmt(high)}, low ${fmt(low)}`;
  }

  get dayTitle() {
    const d = this.route?.day;
    return d ? fmtDayTitle(d) : '';
  }

  get isSquareLoading() {
    return this.hover?.square === 'loading';
  }

  <template>
    <div class="wt-card pointer-events-none w-64 p-3 text-sm" ...attributes>
      {{#if this.hover}}
        {{#if this.route}}
          <p class="wt-eyebrow">On your route ·
            {{fmtKm this.route.km}}
            from the start</p>
          {{#if this.route.day}}
            <p class="wt-title mt-0.5">{{this.dayTitle}}</p>
            {{#if this.route.weather}}
              <dl class="wt-readout mt-2">
                <dt>Low</dt>
                <dd><TempPill @t={{this.route.weather.low}} />
                  <span class="wt-muted text-xs">{{fmtUsual
                      this.route.weather.low
                      this.route.weather.lowSpread
                    }}</span></dd>
                <dt>High</dt>
                <dd><TempPill @t={{this.route.weather.high}} />
                  <span class="wt-muted text-xs">{{fmtUsual
                      this.route.weather.high
                      this.route.weather.highSpread
                    }}</span></dd>
                <dt>Rainy day chance</dt>
                <dd>{{fmtPct this.route.weather.rainChance}}</dd>
                <dt>When it rains</dt>
                <dd>{{fmtMm this.route.weather.wetDayMm}} a day</dd>
                {{#unless this.route.day.isRest}}
                  <dt>Wind</dt>
                  <dd>{{fmtRideWind
                      this.route.day.weather.windSpeed
                      this.route.day.windPush
                    }}</dd>
                {{/unless}}
                <dt>Riding time</dt>
                <dd>{{fmtHours this.route.day.ridingHours}}{{#if
                    this.route.day.needsLights
                  }} 🔦{{/if}}</dd>
                <dt>Daylight</dt>
                <dd>{{fmtDaylight this.route.day.daylight}}</dd>
                {{#if this.route.point.ele}}
                  <dt>Altitude</dt>
                  <dd>{{round this.route.point.ele}}m</dd>
                {{/if}}
                {{#if this.altitudeNote}}
                  <dt>For altitude</dt>
                  <dd>{{this.altitudeNote}}</dd>
                {{/if}}
              </dl>
            {{/if}}
          {{else}}
            <p class="wt-muted mt-1">Beyond the end of the planned days.</p>
          {{/if}}
        {{else if this.hover.climate}}
          <p class="wt-eyebrow">{{this.weekLabel}} · {{this.coords}}</p>
          <dl class="wt-readout mt-2">
            <dt>Low</dt>
            <dd><TempPill @t={{this.hover.climate.low}} />
              <span class="wt-muted text-xs">{{fmtUsual
                  this.hover.climate.low
                  this.hover.climate.lowSpread
                }}</span></dd>
            <dt>High</dt>
            <dd><TempPill @t={{this.hover.climate.high}} />
              <span class="wt-muted text-xs">{{fmtUsual
                  this.hover.climate.high
                  this.hover.climate.highSpread
                }}</span></dd>
            <dt>Rain</dt>
            <dd>{{this.weekRain}}</dd>
            <dt>Rainy days (≥{{this.planner.rainThreshold}}mm)</dt>
            <dd>{{this.weekRainyDays}}</dd>
            <dt>When it rains</dt>
            <dd>{{fmtMm this.hover.climate.wetDayMm}} a day</dd>
            <dt>Wind</dt>
            <dd>{{fmtWind
                this.hover.climate.windSpeed
                this.hover.climate.windU
                this.hover.climate.windV
                (windSteadiness this.hover.climate)
              }}</dd>
          </dl>
        {{else if this.isSquareLoading}}
          <p class="wt-eyebrow">{{this.coords}}</p>
          <p class="wt-muted mt-1">Loading this square's climate…</p>
        {{else if this.hover.square}}
          <p class="wt-eyebrow">{{this.coords}}</p>
          <p class="wt-muted mt-1">Click to load this square's climate.</p>
        {{else}}
          <p class="wt-eyebrow">{{this.coords}}</p>
          <p class="wt-muted mt-1">No climate data here (sea or outside the map
            area).</p>
        {{/if}}
      {{else}}
        <p class="wt-eyebrow">{{this.weekLabel}}</p>
        <p class="wt-muted mt-1">Point at the map for the climate (click an
          outlined square to load it), or at the route for the weather on that
          day of your trip.</p>
      {{/if}}
    </div>
  </template>
}
