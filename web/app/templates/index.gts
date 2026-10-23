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

  get cannotSave() {
    return this.planner.drawn.length < 2;
  }

  undoPoint = () => this.planner.undoDrawnPoint();

  saveDrawing = () => {
    this.planner.finishDrawing('');
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
          <LinkTo @route="help" class="wt-help-link">Help</LinkTo>
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
              <span class="text-sm">Tap the map to add points ({{this.planner.drawn.length}})</span>
              <button
                type="button"
                class="wt-btn"
                {{on "click" this.undoPoint}}
              >Undo</button>
              <button
                type="button"
                class="wt-btn is-primary"
                disabled={{this.cannotSave}}
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
        {{#if this.planner.trip}}
          <section
            class="wt-chart-panel min-w-0 px-4 pt-3 pb-2"
            aria-label="Weather by day"
          >
            <ItineraryChart @trip={{this.planner.trip}} />
          </section>
        {{/if}}
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
        {{#if this.planner.trip}}
          <section
            class="wt-layout-chart wt-chart-panel min-w-0 px-4 pt-3 pb-2"
            aria-label="Weather by day"
          >
            <ItineraryChart @trip={{this.planner.trip}} />
          </section>
        {{/if}}
      </main>
    {{/if}}
  </template>
}
