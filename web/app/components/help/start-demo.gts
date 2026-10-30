import Component from '@glimmer/component';
import type Owner from '@ember/owner';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { waitForPromise } from '@ember/test-waiters';
import { SegmentedControl } from 'frontile/buttons';
import type AtlasService from 'forkcast/services/atlas';
import { climateOn, tileId, type DayClimate } from 'forkcast/utils/climate';
import { fmtDate } from 'forkcast/utils/format';
import { DEFAULTS } from 'forkcast/utils/settings';
import TempCalendar from 'forkcast/components/temp-calendar';
import TempPill from 'forkcast/components/temp-pill';

const PLACES = {
  nordkapp: { name: 'Nordkapp', lat: 71.17, lon: 25.78, ele: 300 },
  edinburgh: { name: 'Edinburgh', lat: 55.95, lon: -3.19, ele: 50 },
  zurich: { name: 'Zürich', lat: 47.37, lon: 8.54, ele: 410 },
  malaga: { name: 'Málaga', lat: 36.72, lon: -4.42, ele: 10 },
};
type PlaceId = keyof typeof PLACES;
type Metric = 'high' | 'low';

/**
 * The start date's calendar, open: each day in the colour of its expected
 * temperature at a starting town, from the same climate data as the map.
 */
export default class StartDemo extends Component {
  @service declare atlas: AtlasService;

  @tracked place: PlaceId = 'edinburgh';
  @tracked metric: Metric = 'high';
  @tracked date = new Date();

  constructor(owner: Owner, args: object) {
    super(owner, args);
    // Straight to the help page, nothing is loaded yet: the climate the
    // planner shows, and the tiles of the towns.
    const tiles = Object.values(PLACES).map((p) => tileId(p.lat, p.lon));
    void waitForPromise(
      this.atlas.show().then(() => this.atlas.want('help', tiles)),
    );
  }

  places = (Object.keys(PLACES) as PlaceId[]).map((id) => ({
    id,
    name: PLACES[id].name,
  }));

  weatherOn(date: Date): DayClimate | undefined {
    const climate = this.atlas.climate;
    return (
      climate &&
      climateOn(climate, date, PLACES[this.place], DEFAULTS.rainThreshold)
    );
  }

  tempOn = (date: Date) => {
    const t = this.weatherOn(date)?.[this.metric];
    return t === undefined || Number.isNaN(t) ? undefined : t;
  };

  get tempLabel() {
    const what = this.metric === 'high' ? 'High' : 'Low';
    return `${what} in ${PLACES[this.place].name}`;
  }

  get picked() {
    return this.weatherOn(this.date);
  }

  setPlace = (v: PlaceId) => {
    this.place = v;
  };
  setMetric = (v: Metric) => {
    this.metric = v;
  };
  setDate = (d: Date | null) => {
    if (d) this.date = d;
  };

  <template>
    <div class="wt-help-demo flex flex-col gap-3">
      <SegmentedControl
        @value={{this.place}}
        @onChange={{this.setPlace}}
        @size="sm"
        aria-label="Starting town"
        as |Ctl|
      >
        {{#each this.places as |p|}}
          <Ctl.Item @value={{p.id}}>{{p.name}}</Ctl.Item>
        {{/each}}
      </SegmentedControl>
      <SegmentedControl
        @value={{this.metric}}
        @onChange={{this.setMetric}}
        @size="sm"
        aria-label="Temperature"
        as |Ctl|
      >
        <Ctl.Item @value="high">High</Ctl.Item>
        <Ctl.Item @value="low">Low</Ctl.Item>
      </SegmentedControl>
      <div class="wt-help-calendar">
        <TempCalendar
          @value={{this.date}}
          @onChange={{this.setDate}}
          @tempOn={{this.tempOn}}
          @tempLabel={{this.tempLabel}}
          aria-label="Start date"
        />
      </div>
      <dl class="wt-inline-stats">
        <div><dt>Start</dt><dd>{{fmtDate this.date}}</dd></div>
        <div><dt>Low</dt><dd><TempPill @t={{this.picked.low}} /></dd></div>
        <div><dt>High</dt><dd><TempPill @t={{this.picked.high}} /></dd></div>
      </dl>
    </div>
  </template>
}
