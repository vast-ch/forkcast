import Component from '@glimmer/component';
import { service } from '@ember/service';
import type PlannerService from 'forkcast/services/planner';
import { TEMP_STOPS } from 'forkcast/utils/climate';
import { css } from 'forkcast/utils/format';

const DOT_STEPS = {
  mm: [
    { label: '25', value: 25 },
    { label: '75', value: 75 },
    { label: '150', value: 150 },
    { label: '250 mm', value: 250 },
  ],
  days: [
    { label: '2', value: 2 },
    { label: '5', value: 5 },
    { label: '10', value: 10 },
    { label: '20 days', value: 20 },
  ],
};

export default class Legend extends Component<{ Element: HTMLDivElement }> {
  @service declare planner: PlannerService;

  get gradient() {
    const lo = TEMP_STOPS[0]![0];
    const hi = TEMP_STOPS[TEMP_STOPS.length - 1]![0];
    const stops = TEMP_STOPS.map(
      ([t, c]) => `${c} ${((t - lo) / (hi - lo)) * 100}%`,
    );
    return `linear-gradient(to right, ${stops.join(', ')})`;
  }

  get ticks() {
    return [-10, 0, 10, 20, 30].map((t) => ({
      t,
      left: ((t + 15) / 50) * 100,
    }));
  }

  get dots() {
    const full = this.planner.rainMetric === 'mm' ? 250 : 20;
    return DOT_STEPS[this.planner.rainMetric].map((d) => ({
      ...d,
      size: Math.max(3, 18 * Math.sqrt(d.value / full)),
    }));
  }

  get tempLabel() {
    return this.planner.tempMetric === 'high'
      ? 'Average day high'
      : 'Average night low';
  }

  get rainLabel() {
    return this.planner.rainMetric === 'mm'
      ? 'Rain per month'
      : `Days with ${this.planner.rainThreshold} mm or more per month`;
  }

  <template>
    <div
      class="wt-card wt-legend flex flex-wrap items-end gap-x-6 gap-y-3 px-3 py-2.5 text-xs"
      ...attributes
    >
      {{#if this.planner.showTemp}}
        <div class="min-w-0">
          <p class="wt-eyebrow">{{this.tempLabel}}</p>
          <div
            class="relative mt-1.5 h-2.5 w-48 rounded-sm"
            style={{css "background: " this.gradient}}
          ></div>
          <div class="relative h-4 w-48 tabular-nums">
            {{#each this.ticks as |tick|}}
              <span
                class="wt-tick"
                style={{css "left: " tick.left "%"}}
              >{{tick.t}}°</span>
            {{/each}}
          </div>
        </div>
      {{/if}}
      {{#if this.planner.showRain}}
        <div>
          <p class="wt-eyebrow">{{this.rainLabel}}</p>
          <div class="mt-1 flex items-end gap-3 tabular-nums">
            {{#each this.dots as |dot|}}
              <span class="flex items-center gap-1">
                <span
                  class="wt-dot"
                  style={{css "width: " dot.size "px; height: " dot.size "px"}}
                ></span>
                {{dot.label}}
              </span>
            {{/each}}
          </div>
        </div>
      {{/if}}
    </div>
  </template>
}
