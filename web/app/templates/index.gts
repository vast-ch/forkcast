import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { LinkTo } from '@ember/routing';
import { on } from '@ember/modifier';
import { Drawer } from 'frontile/overlays';
import SlidersHorizontal from 'ember-phosphor-icons/components/ph-sliders-horizontal';
import type PlannerService from 'forkcast/services/planner';
import type AtlasService from 'forkcast/services/atlas';
import type MediaService from 'forkcast/services/media';
import SidePanel from 'forkcast/components/side-panel';
import WheelMap from 'forkcast/components/wheel-map';
import HoverCard from 'forkcast/components/hover-card';
import Legend from 'forkcast/components/legend';
import ItineraryChart from 'forkcast/components/itinerary-chart';
import Logo from 'forkcast/components/logo';
import HelpLink from 'forkcast/components/help-link';
import RouteEditor from 'forkcast/components/route-editor';
import type { TOC } from '@ember/component/template-only';
import type { Trip } from 'forkcast/utils/itinerary';
import type { Ride } from 'forkcast/services/planner';
import { btnPrimary } from 'forkcast/utils/classes';

/** The day-by-day chart under the map, once there is a trip. */
const ChartPanel: TOC<{
  Args: { rows: { ride: Ride; trip: Trip }[] };
  Element: HTMLElement;
}> = <template>
  {{#if @rows.length}}
    <section
      class="min-w-0 border-t border-wt-line bg-wt-paper px-4 pt-3 pb-2"
      aria-label="Weather by day"
      ...attributes
    >
      <ItineraryChart @rows={{@rows}} />
    </section>
  {{/if}}
</template>;

export default class IndexTemplate extends Component {
  @service declare planner: PlannerService;
  @service declare atlas: AtlasService;
  @service declare media: MediaService;

  @tracked isSettingsOpen = false;

  openSettings = () => {
    this.isSettingsOpen = true;
  };

  closeSettings = () => {
    this.isSettingsOpen = false;
  };

  /** The drawer steps aside while a route is being drawn on the map. */
  get showSettings() {
    return this.isSettingsOpen && !this.planner.isDrawing;
  }

  <template>
    {{#if this.media.isPhone}}
      {{! Phones: map first, the trip below it, every setting in a drawer.
          Each part keeps its full height and the page scrolls: the panel's
          desktop sizing (shrink to fit, scroll inside) would squeeze the trip
          overview into whatever is left under the map. }}
      <main class="wt-phone flex h-full flex-col overflow-y-auto *:flex-none">
        <header
          class="sticky top-0 z-[1100] flex items-center gap-3 border-b border-wt-line bg-wt-paper px-4 py-2"
        >
          <LinkTo
            @route="index"
            aria-label="Forkcast home"
            class="mr-auto min-w-0"
          >
            <Logo @isSmall={{true}} />
          </LinkTo>
          <HelpLink @iconClass="size-6" />
          <button
            type="button"
            class="{{btnPrimary}} gap-1.5"
            aria-haspopup="dialog"
            aria-expanded={{if this.isSettingsOpen "true" "false"}}
            {{on "click" this.openSettings}}
          ><SlidersHorizontal class="size-4" aria-hidden="true" />
            Settings</button>
        </header>
        {{! isolate: Leaflet's z-indexes (up to 1000) stay inside the map, so
            drawers and the phone bar stay on top. }}
        <section
          class="wt-phone-map relative isolate h-[58vh] min-h-[300px]"
          aria-label="Map"
        >
          <WheelMap />
          <Legend class="absolute bottom-[1.6rem] left-2 z-[1000]" />
          {{#if this.planner.isDrawing}}
            {{! Drawing needs the map, so the drawer closes and these take over. }}
            <RouteEditor
              class="absolute top-2 right-2 left-14 z-[1000] bg-wt-paper/94 px-2.5 py-2"
              @onSave={{this.closeSettings}}
            />
          {{/if}}
        </section>
        <ChartPanel @rows={{this.planner.planned}} />
      </main>
      {{#if this.showSettings}}
        <Drawer
          @allowCloseButton={{true}}
          @isOpen={{this.showSettings}}
          @onClose={{this.closeSettings}}
          @placement="right"
          @size="lg"
          @variant="flat"
          as |drawer|
        >
          <drawer.Header @title="Settings" />
          <drawer.Body>
            <SidePanel @part="settings" />
          </drawer.Body>
        </Drawer>
      {{/if}}
    {{else}}
      {{! Panel on the left, the map and the day chart on the right. }}
      <main
        class="grid h-full grid-cols-[500px_minmax(0,1fr)] grid-rows-[minmax(0,1fr)_auto] overflow-hidden"
      >
        <SidePanel class="row-span-2 overflow-hidden border-r border-wt-line" />
        <section class="relative isolate min-h-0" aria-label="Map">
          <WheelMap />
          <HoverCard class="absolute top-3 right-3 z-[1000]" />
          <Legend class="absolute bottom-6 left-3 z-[1000]" />
        </section>
        <ChartPanel @rows={{this.planner.planned}} class="col-start-2" />
      </main>
    {{/if}}
  </template>
}
