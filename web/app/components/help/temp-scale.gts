import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import RangeInput from 'forkcast/components/range-input';
import TempPill from 'forkcast/components/temp-pill';

/** The temperature colours, as the app's own pills: a scale, and one to try. */
export default class TempScale extends Component {
  @tracked t = 18;

  get value() {
    return String(this.t);
  }

  scale = [-15, -10, -5, 0, 5, 10, 15, 20, 25, 30, 35];

  setT = (v: string) => {
    this.t = Number(v);
  };

  <template>
    <div class="wt-help-demo">
      <div class="flex flex-wrap gap-1.5">
        {{#each this.scale as |t|}}
          <TempPill @t={{t}} />
        {{/each}}
      </div>
      <div class="mt-4 flex items-center gap-3">
        <RangeInput
          @label="Try a temperature"
          @value={{this.value}}
          @onInput={{this.setT}}
          min="-20"
          max="40"
          step="1"
          class="min-w-0 flex-1"
        />
        <TempPill @t={{this.t}} />
      </div>
    </div>
  </template>
}
