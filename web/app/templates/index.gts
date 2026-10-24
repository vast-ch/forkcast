import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { LinkTo } from '@ember/routing';
import { on } from '@ember/modifier';
import { Drawer } from 'frontile/overlays';
import { Switch } from 'frontile/forms';
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
import { not } from 'forkcast/utils/helpers';
import type { TOC } from '@ember/component/template-only';
import type { Trip } from 'forkcast/utils/itinerary';

/** The day-by-day chart under the map, once there is a trip. */
const ChartPanel: TOC<{ Args: { trip?: Trip }; Element: HTMLElement }> =
  <template>
    {{#if @trip}}
      <section
        class="wt-chart-panel min-w-0 px-4 pt-3 pb-2"
        aria-label="Weather by day"
        ...attributes
      >
        <ItineraryChart @trip={{@trip}} />
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

  undoPoint = () => this.planner.undoDrawnPoint();
  toggleSnap = () => this.planner.toggleSnap();

  saveDrawing = () => {
    this.planner.finishDrawing();
    this.isSettingsOpen = false;
  };

  cancelDrawing = () => this.planner.cancelDrawing();

  <template>
    {{#if this.media.isPhone}}
      {{! Phones: map first, the trip below it, every setting in a drawer. }}
      <main class="wt-shell wt-phone">
        <header class="wt-phone-bar">
          <LinkTo @route="index" aria-label="Forkcast home" class="min-w-0">
            <Logo class="wt-logo-small" />
          </LinkTo>
          <HelpLink @iconClass="size-6" />
          <button
            type="button"
            class="wt-btn is-primary"
            aria-haspopup="dialog"
            aria-expanded={{if this.isSettingsOpen "true" "false"}}
            {{on "click" this.openSettings}}
          ><SlidersHorizontal class="size-4" aria-hidden="true" />
            Settings</button>
        </header>
        <section class="wt-phone-map relative" aria-label="Map">
          <WheelMap />
          <Legend class="absolute bottom-6 left-3 z-[1000]" />
          {{#if this.planner.isDrawing}}
            {{! Drawing needs the map, so the drawer closes and these take over. }}
            <div
              class="wt-draw-bar"
              role="toolbar"
              aria-label="Drawing a route"
            >
              <Switch
                @label="Follow routes"
                @size="sm"
                @isSelected={{this.planner.snapToRoutes}}
                @onChange={{this.toggleSnap}}
              />
              <button
                type="button"
                class="wt-btn"
                {{on "click" this.undoPoint}}
              >Undo</button>
              <button
                type="button"
                class="wt-btn is-primary"
                disabled={{not this.planner.canFinishDrawing}}
                {{on "click" this.saveDrawing}}
              >Save</button>
              <button
                type="button"
                class="wt-btn is-ghost"
                {{on "click" this.cancelDrawing}}
              >Cancel</button>
            </div>
          {{/if}}
        </section>
        <ChartPanel @trip={{this.planner.trip}} />
        <SidePanel @part="overview" class="wt-phone-overview" />
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
      <main class="wt-shell wt-layout">
        <SidePanel class="wt-layout-panel" />
        <section class="wt-layout-map relative min-h-0" aria-label="Map">
          <WheelMap />
          <HoverCard class="absolute top-3 right-3 z-[1000]" />
          <Legend class="absolute bottom-6 left-3 z-[1000]" />
        </section>
        <ChartPanel @trip={{this.planner.trip}} class="wt-layout-chart" />
      </main>
    {{/if}}
  </template>
}
