import Component from '@glimmer/component';
import { Calendar, type CalendarArgs } from 'frontile/collections';
import { tempColor, tempInk } from 'forkcast/utils/climate';
import { css, fmtTemp } from 'forkcast/utils/format';

interface TempCalendarSignature {
  Args: {
    value: Date | null;
    onChange: (date: Date | null) => void;
    /** The temperature on a day, or undefined where there is no data. */
    tempOn: (date: Date) => number | undefined;
    /** What the temperature is, for each day's tooltip: "High at the start". */
    tempLabel: string;
    /** Passed on from a DatePicker's `:calendar` block. */
    color?: CalendarArgs['color'];
    locale?: string;
    labelledBy?: string;
    autofocus?: boolean;
  };
  Element: HTMLDivElement;
}

/**
 * Frontile's calendar with each day filled in the map's colour for its
 * temperature. Inset inside the day button, so a selected day's fill shows
 * as a ring around it.
 */
export default class TempCalendar extends Component<TempCalendarSignature> {
  swatch = (date: Date) => {
    const t = this.args.tempOn(date);
    if (t === undefined) return undefined;
    return {
      style: css('background: ', tempColor(t), '; color: ', tempInk(t)),
      title: `${this.args.tempLabel}: ${fmtTemp(t)}`,
    };
  };

  <template>
    <Calendar
      @color={{@color}}
      @value={{@value}}
      @onChange={{@onChange}}
      @locale={{@locale}}
      @weekStartsOn={{1}}
      @labelledBy={{@labelledBy}}
      @autofocus={{@autofocus}}
      ...attributes
    >
      <:day as |day|>
        {{#let (this.swatch day.date) as |swatch|}}
          <span
            class="wt-temp-day
              {{if day.isOutside 'is-outside'}}
              {{if swatch 'has-temp'}}"
            style={{swatch.style}}
            title={{swatch.title}}
          >{{day.dayOfMonth}}</span>
        {{/let}}
      </:day>
    </Calendar>
  </template>
}
