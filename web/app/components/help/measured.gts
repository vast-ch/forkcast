import Component from '@glimmer/component';
import type Owner from '@ember/owner';
import { tracked } from '@glimmer/tracking';
import { loadMeasurements, type Measurements } from 'forkcast/utils/verify';

interface Signature {
  Args: object;
  Blocks: { default: [Measurements] };
}

/**
 * Loads the data's measured precision and yields it, for the nerd pages'
 * tables; says when and with which code it was measured.
 */
export default class Measured extends Component<Signature> {
  @tracked data?: Measurements;
  @tracked failed = false;

  constructor(owner: Owner, args: Signature['Args']) {
    super(owner, args);
    loadMeasurements().then(
      (m) => (this.data = m),
      () => (this.failed = true),
    );
  }

  <template>
    {{#if this.data}}
      {{yield this.data}}
      <p class="wt-help-measured-at">Measured on
        {{this.data.run.date}}
        by the data pipeline's verify step (code
        <code>{{this.data.run.code}}</code>, grids
        <code>{{this.data.run.grids}}</code>).</p>
    {{else if this.failed}}
      <p class="wt-help-measured-at">The measurements couldn't be loaded.</p>
    {{else}}
      <p class="wt-help-measured-at">Loading the measurements…</p>
    {{/if}}
  </template>
}
