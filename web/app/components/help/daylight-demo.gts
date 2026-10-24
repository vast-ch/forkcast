import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { fn } from '@ember/helper';
import { DatePicker, Input } from 'frontile/forms';
import { SegmentedControl } from 'frontile/buttons';
import { daylightHours } from 'forkcast/utils/sun';
import { fmtDaylight, fmtHours } from 'forkcast/utils/format';

const PLACES = {
  nordkapp: { name: 'Nordkapp', lat: 71.17, lon: 25.78 },
  edinburgh: { name: 'Edinburgh', lat: 55.95, lon: -3.19 },
  zurich: { name: 'Zürich', lat: 47.37, lon: 8.54 },
  malaga: { name: 'Málaga', lat: 36.72, lon: -4.42 },
};
type PlaceId = keyof typeof PLACES;

/**
 * Daylight against riding time, with the app's own calculation: when a day
 * gets the 🔦 in the chart.
 */
export default class DaylightDemo extends Component {
  @tracked place: PlaceId = 'zurich';
  @tracked date = new Date();
  @tracked km = 80;
  @tracked speed = 21;

  places = (Object.keys(PLACES) as PlaceId[]).map((id) => ({
    id,
    name: PLACES[id].name,
  }));

  get kmValue() {
    return String(this.km);
  }

  get speedValue() {
    return String(this.speed);
  }

  get daylight() {
    const p = PLACES[this.place];
    return daylightHours(this.date, p, p);
  }

  get riding() {
    return this.km / this.speed;
  }

  get needsLights() {
    return this.riding > this.daylight;
  }

  setPlace = (v: PlaceId) => {
    this.place = v;
  };
  setDate = (d: Date | null) => {
    if (d) this.date = d;
  };
  setNumber = (key: 'km' | 'speed', v: string) => {
    const n = Number(v);
    if (n > 0) this[key] = n;
  };

  <template>
    <div class="wt-help-demo flex flex-col gap-3">
      <SegmentedControl
        @value={{this.place}}
        @onChange={{this.setPlace}}
        @size="sm"
        aria-label="Place"
        as |Ctl|
      >
        {{#each this.places as |p|}}
          <Ctl.Item @value={{p.id}}>{{p.name}}</Ctl.Item>
        {{/each}}
      </SegmentedControl>
      <div class="grid grid-cols-3 gap-2">
        <DatePicker
          @label="Date"
          @inputSize="sm"
          @value={{this.date}}
          @onChange={{this.setDate}}
          @weekStartsOn={{1}}
        />
        <Input
          @label="km per day"
          @type="number"
          @size="sm"
          @value={{this.kmValue}}
          @onInput={{fn this.setNumber "km"}}
          min="5"
        />
        <Input
          @label="Avg speed (km/h)"
          @type="number"
          @size="sm"
          @value={{this.speedValue}}
          @onInput={{fn this.setNumber "speed"}}
          min="5"
        />
      </div>
      <dl class="wt-inline-stats">
        <div><dt>Daylight</dt><dd>{{fmtDaylight this.daylight}}</dd></div>
        <div><dt>Riding</dt><dd>{{fmtHours this.riding}}</dd></div>
        <div><dt>In the chart</dt><dd>{{if
              this.needsLights
              "🔦 needs lights"
              "no 🔦"
            }}</dd></div>
      </dl>
    </div>
  </template>
}
