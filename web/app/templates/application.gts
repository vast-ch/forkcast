import { pageTitle } from 'ember-page-title';
import { service } from '@ember/service';
import Component from '@glimmer/component';
import { PortalTarget } from 'frontile/overlays';
import type AtlasService from 'forkcast/services/atlas';
import { card, title } from 'forkcast/utils/classes';

export default class Application extends Component {
  @service declare atlas: AtlasService;

  <template>
    {{pageTitle "Forkcast"}}
    {{#if this.atlas.error}}
      <main class="grid h-full place-items-center p-6">
        <div class="{{card}} max-w-lg p-5">
          <h1 class={{title}}>The map data is missing</h1>
          <p class="mt-2 text-sm">{{this.atlas.error}}</p>
        </div>
      </main>
    {{else}}
      {{outlet}}
    {{/if}}
    {{! Frontile renders overlays (the phone settings drawer, popovers) here.
        Its theme gives popovers (the only overlays with a placement) a faint
        border and no shadow, so they blend into the panel behind: a clear
        edge and lift in the app's own colours. }}
    <PortalTarget
      class="relative z-[2001] [&_[data-component=overlay][data-placement]]:border-wt-border [&_[data-component=overlay][data-placement]]:shadow-wt-popover"
    />
  </template>
}
