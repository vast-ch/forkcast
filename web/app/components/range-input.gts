import type { TOC } from '@ember/component/template-only';
import { hash } from '@ember/helper';
import { Input } from 'frontile/forms';

/** Tailwind finds classes by their full names, so each part is spelled out. */
const inputClass = [
  'h-6 w-full cursor-pointer border-0 bg-transparent p-0 shadow-none focus:ring-0',
  'focus-visible:rounded focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-wt-accent',
  '[&::-webkit-slider-runnable-track]:h-1.5 [&::-webkit-slider-runnable-track]:rounded-full [&::-webkit-slider-runnable-track]:bg-wt-line',
  '[&::-moz-range-track]:h-1.5 [&::-moz-range-track]:rounded-full [&::-moz-range-track]:bg-wt-line',
  '[&::-webkit-slider-thumb]:-mt-[5px] [&::-webkit-slider-thumb]:size-4 [&::-webkit-slider-thumb]:appearance-none [&::-webkit-slider-thumb]:rounded-full [&::-webkit-slider-thumb]:border-2 [&::-webkit-slider-thumb]:border-white [&::-webkit-slider-thumb]:bg-wt-ink [&::-webkit-slider-thumb]:shadow-[0_0_0_1px_var(--color-wt-ink)]',
  '[&::-moz-range-thumb]:size-4 [&::-moz-range-thumb]:rounded-full [&::-moz-range-thumb]:border-2 [&::-moz-range-thumb]:border-white [&::-moz-range-thumb]:bg-wt-ink [&::-moz-range-thumb]:shadow-[0_0_0_1px_var(--color-wt-ink)]',
].join(' ');

/**
 * A slider: Frontile's range Input (so it keeps its label and accessibility
 * wiring) without the text-field box: a thin track and a round thumb (the
 * input's own parts, reached through their vendor pseudo-elements).
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
      input=inputClass
    }}
    ...attributes
  />
</template>;

export default RangeInput;
