import type { TOC } from '@ember/component/template-only';
import { hash } from '@ember/helper';
import { Input } from 'frontile/forms';

/**
 * A slider: Frontile's range Input (so it keeps its label and accessibility
 * wiring) without the text-field box, the track and thumb styled by .wt-range.
 */
const RangeInput: TOC<{
  Args: {
    value: string;
    onInput: (value: string) => void;
    label?: string;
  };
  Element: HTMLInputElement;
}> = <template>
  {{! `input` below is Frontile's class slot, not an event handler. }}
  {{! template-lint-disable no-passed-in-event-handlers }}
  <Input
    @type="range"
    @label={{@label}}
    @value={{@value}}
    @onInput={{@onInput}}
    @classes={{hash
      innerContainer="border-0 bg-transparent p-0 shadow-none"
      input="wt-range h-6 border-0 bg-transparent p-0 shadow-none focus:ring-0"
    }}
    ...attributes
  />
</template>;

export default RangeInput;
