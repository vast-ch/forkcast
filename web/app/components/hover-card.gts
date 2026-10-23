import Component from '@glimmer/component';
import { service } from '@ember/service';
import type PlannerService from 'forkcast/services/planner';
import { tempSwatch } from 'forkcast/utils/climate';
import { isMissing } from 'forkcast/utils/helpers';
import {
  css,
  fmtDayTitle,
  fmtKm,
  fmtMm,
  fmtPct,
  fmtTemp,
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

  /** How much the temperatures were shifted for the route's height, if noticeably. */
  get altitudeNote() {
    const shift = this.route?.weather?.altitudeShift ?? 0;
    if (Math.abs(shift) < 0.5) return '';
    return `${shift > 0 ? '+' : '−'}${Math.abs(shift).toFixed(1)}°`;
  }

  get dayTitle() {
    const d = this.route?.day;
    return d ? fmtDayTitle(d) : '';
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
                <dt>High / low</dt>
                <dd>
                  <span
                    class="wt-chip"
                    style={{css
                      "background: "
                      (tempSwatch this.route.weather.high)
                    }}
                  ></span>
                  {{fmtTemp this.route.weather.high}}
                  /
                  {{fmtTemp this.route.weather.low}}
                </dd>
                <dt>Rainy day chance</dt>
                <dd>{{fmtPct this.route.weather.rainChance}}</dd>
                <dt>Rain, average</dt>
                <dd>{{fmtMm this.route.weather.rainMm}} / day</dd>
                {{#if this.route.point.ele}}
                  <dt>Altitude</dt>
                  <dd>{{round this.route.point.ele}} m</dd>
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
        {{else if this.hover.month}}
          <p class="wt-eyebrow">{{this.weekLabel}} average · {{this.coords}}</p>
          <dl class="wt-readout mt-2">
            <dt>Day high</dt>
            <dd>
              <span
                class="wt-chip"
                style={{css "background: " (tempSwatch this.hover.month.high)}}
              ></span>
              {{fmtTemp this.hover.month.high}}
            </dd>
            <dt>Night low</dt>
            <dd>{{fmtTemp this.hover.month.low}}</dd>
            <dt>Rain</dt>
            <dd>{{fmtMm this.hover.month.monthRainMm}} / month</dd>
            <dt>Rainy days (≥ {{this.planner.rainThreshold}} mm)</dt>
            <dd>{{round this.hover.month.monthWetDays}}</dd>
          </dl>
        {{else}}
          <p class="wt-eyebrow">{{this.coords}}</p>
          <p class="wt-muted mt-1">No climate data here (sea or outside the map
            area).</p>
        {{/if}}
      {{else}}
        <p class="wt-eyebrow">{{this.weekLabel}} average</p>
        <p class="wt-muted mt-1">Point at the map for the climate, or at the
          route for the weather on that day of your trip.</p>
      {{/if}}
    </div>
  </template>
}
