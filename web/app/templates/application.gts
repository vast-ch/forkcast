import { pageTitle } from 'ember-page-title';
import { service } from '@ember/service';
import Component from '@glimmer/component';
import type AtlasService from 'forkcast/services/atlas';

export default class Application extends Component {
  @service declare atlas: AtlasService;

  <template>
    {{pageTitle "Forkcast"}}
    {{#if this.atlas.error}}
      <main class="wt-shell grid place-items-center p-6">
        <div class="wt-card max-w-lg p-5">
          <h1 class="wt-title">The map data is missing</h1>
          <p class="mt-2 text-sm">{{this.atlas.error}}</p>
        </div>
      </main>
    {{else}}
      {{outlet}}
    {{/if}}
  </template>
}
