import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import RangeInput from 'forkcast/components/range-input';
import { lapseRateAt, MONTHS } from 'forkcast/utils/climate';
import TempPill from 'forkcast/components/temp-pill';

/**
 * The altitude correction with the app's own seasonal rates: how much warmer
 * or colder a point is than its 25 km grid cell.
 */
export default class AltitudeDemo extends Component {
  @tracked month = 0;
  @tracked diff = 800;

  /** The cell's average high in the example, °C. */
  cellHigh = 10;

  get rate() {
    return lapseRateAt((this.month + 0.5) / 12);
  }

  get shift() {
    return -this.rate * this.diff;
  }

  get monthValue() {
    return String(this.month);
  }

  get diffValue() {
    return String(this.diff);
  }

  get monthName() {
    return MONTHS[this.month];
  }

  get ratePerKm() {
    return (this.rate * 1000).toFixed(1);
  }

  get shiftText() {
    const s = this.shift;
    if (Math.abs(s) < 0.05) return 'no change';
    return `${s > 0 ? '+' : '−'}${Math.abs(s).toFixed(1)}°C`;
  }

  get heightText() {
    const d = this.diff;
    if (d === 0) return 'at the cell’s height';
    return `${Math.abs(d)}m ${d > 0 ? 'above' : 'below'} the cell`;
  }

  setMonth = (v: string) => {
    this.month = Number(v);
  };
  setDiff = (v: string) => {
    this.diff = Number(v);
  };

  <template>
    <div class="wt-help-demo flex flex-col gap-3">
      <RangeInput
        @label="Month: {{this.monthName}}"
        @value={{this.monthValue}}
        @onInput={{this.setMonth}}
        min="0"
        max="11"
        step="1"
      />
      <RangeInput
        @label="Your point: {{this.heightText}}"
        @value={{this.diffValue}}
        @onInput={{this.setDiff}}
        min="-1500"
        max="1500"
        step="100"
      />
      <dl class="wt-inline-stats">
        <div><dt>Rate</dt><dd>{{this.ratePerKm}}°C per 1,000m</dd></div>
        <div><dt>Correction</dt><dd>{{this.shiftText}}</dd></div>
        <div><dt>Cell high</dt><dd><TempPill @t={{this.cellHigh}} /></dd></div>
        <div><dt>Your point</dt><dd><TempPill @t={{this.adjusted}} /></dd></div>
      </dl>
    </div>
  </template>

  get adjusted() {
    return this.cellHigh + this.shift;
  }
}
