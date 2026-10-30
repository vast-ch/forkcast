import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import type PlannerService from 'forkcast/services/planner';
import { DAYS_PER_MONTH, TEMP_STOPS } from 'forkcast/utils/climate';
import { css } from 'forkcast/utils/format';
import { DOT_FULL, rainEmojiTiers } from 'forkcast/utils/layers';

/** The legend's sample dots, as mm in the week shown. */
const DOT_STEPS = [
  { label: '5', value: 5 },
  { label: '15', value: 15 },
  { label: '30', value: 30 },
  { label: '60mm', value: 60 },
];

export default class Legend extends Component<{ Element: HTMLButtonElement }> {
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

  /** The emoji steps for the rainy-day threshold chosen. */
  get rainEmoji() {
    return rainEmojiTiers(this.planner.rainThreshold);
  }

  get isEmoji() {
    return this.planner.rainMetric === 'days';
  }

  /** Sized like the map's dots, which scale with the rate (see rainDots). */
  get dots() {
    const full = DOT_FULL.mm;
    const toMonth = DAYS_PER_MONTH / this.planner.weekSlot.days;
    return DOT_STEPS.map((d) => ({
      ...d,
      size: Math.max(
        3,
        18 * Math.sqrt(Math.min(1, (d.value * toMonth) / full)),
      ),
    }));
  }

  get tempLabel() {
    return this.planner.tempMetric === 'high' ? 'Average high' : 'Average low';
  }

  get rainLabel() {
    return this.planner.rainMetric === 'mm'
      ? 'Rain per week'
      : `Rainy days a week (${this.planner.rainThreshold}mm or more)`;
  }

  /** Collapsed to a small chip; it stays out of the way of the map. Not kept
   * across visits: it's a view choice, not part of the plan. */
  @tracked isOpen = true;

  toggle = () => {
    this.isOpen = !this.isOpen;
  };

  get buttonLabel() {
    if (!this.isOpen) return 'Show the legend';
    const parts = [
      this.planner.showTemp ? this.tempLabel : '',
      this.planner.showRain ? this.rainLabel : '',
    ].filter(Boolean);
    return `Legend: ${parts.join('; ')}. Hide the legend`;
  }

  /** Nothing to explain when both layers are off. */
  get hasContent() {
    return this.planner.showTemp || this.planner.showRain;
  }

  <template>
    {{#if this.hasContent}}
      {{! The whole legend is the toggle: click to shrink it to a chip and back. }}
      <button
        type="button"
        class="wt-card wt-legend flex flex-wrap items-end gap-x-6 gap-y-3 px-3 py-2.5 text-left text-xs
          {{unless this.isOpen 'is-closed'}}"
        aria-expanded={{if this.isOpen "true" "false"}}
        aria-label={{this.buttonLabel}}
        title={{if this.isOpen "Hide the legend" "Show the legend"}}
        {{on "click" this.toggle}}
        ...attributes
      >
        {{#if this.isOpen}}
          {{#if this.planner.showTemp}}
            <span class="block min-w-0">
              <span
                class="wt-legend-scale relative mt-0.5 block h-2.5 rounded-sm"
                style={{css "background: " this.gradient}}
              ></span>
              <span class="wt-legend-scale relative block h-4 tabular-nums">
                {{#each this.ticks as |tick|}}
                  <span
                    class="wt-tick"
                    style={{css "left: " tick.left "%"}}
                  >{{tick.t}}<span class="wt-tick-unit">°C</span></span>
                {{/each}}
              </span>
            </span>
          {{/if}}
          {{#if this.planner.showRain}}
            {{#if this.isEmoji}}
              <span
                class="wt-legend-emoji flex items-center gap-3 tabular-nums"
                title={{this.rainLabel}}
              >
                {{#each this.rainEmoji as |t|}}
                  <span class="flex items-center gap-1">
                    <span
                      aria-hidden="true"
                      style={{css "font-size: " t.px "px; line-height: 1"}}
                    >{{t.emoji}}</span>
                    {{t.label}}
                  </span>
                {{/each}}
              </span>
            {{else}}
              <span class="wt-legend-dots flex items-end gap-3 tabular-nums">
                {{#each this.dots as |dot|}}
                  <span class="flex items-center gap-1">
                    <span
                      class="wt-dot"
                      style={{css
                        "width: "
                        dot.size
                        "px; height: "
                        dot.size
                        "px"
                      }}
                    ></span>
                    {{dot.label}}
                  </span>
                {{/each}}
              </span>
            {{/if}}
          {{/if}}
        {{else}}
          <span
            class="block h-2 w-8 rounded-sm"
            style={{css "background: " this.gradient}}
          ></span>
          {{#if this.isEmoji}}
            <span aria-hidden="true">🌧️</span>
          {{else}}
            <span class="wt-dot" style={{css "width: 8px; height: 8px"}}></span>
          {{/if}}
        {{/if}}
      </button>
    {{/if}}
  </template>
}
