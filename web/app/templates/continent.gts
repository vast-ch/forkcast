import Component from '@glimmer/component';
import { service } from '@ember/service';
import type PlannerService from 'wheelther/services/planner';
import SidePanel from 'wheelther/components/side-panel';
import WheelMap from 'wheelther/components/wheel-map';
import HoverCard from 'wheelther/components/hover-card';
import Legend from 'wheelther/components/legend';
import ItineraryChart from 'wheelther/components/itinerary-chart';

export default class ContinentTemplate extends Component {
  @service declare planner: PlannerService;

  <template>
    <main class="wt-shell wt-layout">
      <SidePanel class="wt-layout-panel" />
      <section class="wt-layout-map relative min-h-0" aria-label="Map">
        <WheelMap />
        <HoverCard class="absolute top-3 right-3 z-[1000] hidden sm:block" />
        <Legend class="absolute bottom-6 left-3 z-[1000]" />
      </section>
      {{#if this.planner.trip}}
        <section
          class="wt-layout-chart wt-chart-panel min-w-0 px-4 pt-3 pb-2"
          aria-label="Weather by day"
        >
          <ItineraryChart @trip={{this.planner.trip}} />
        </section>
      {{/if}}
    </main>
  </template>
}
