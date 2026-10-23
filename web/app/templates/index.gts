import Component from '@glimmer/component';
import { service } from '@ember/service';
import { cached, tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';
import type RouterService from '@ember/routing/router-service';
import type AtlasService from 'wheelther/services/atlas';

/** The continent picker: a clickable world map. */
export default class IndexTemplate extends Component {
  @service declare atlas: AtlasService;
  @service declare router: RouterService;

  @tracked hovered?: string;

  @cached
  get shapes() {
    const world = this.atlas.world ?? {};
    return this.atlas.continents.map((c) => ({
      id: c.id,
      name: c.name,
      d: world[c.id] ?? '',
      href: this.router.urlFor('continent', c.id),
    }));
  }

  get other() {
    return this.atlas.world?.['other'] ?? '';
  }

  get caption() {
    return this.atlas.continents.find((c) => c.id === this.hovered)?.name;
  }

  isHovered = (id: string) => this.hovered === id;

  hover = (id: string | undefined) => {
    this.hovered = id;
  };

  open = (id: string, e: MouseEvent) => {
    e.preventDefault();
    void this.router.transitionTo('continent', id);
  };

  <template>
    {{pageTitle "Wheelther"}}
    <div class="wt-picker">
      <header class="wt-picker-header">
        <div class="flex items-baseline justify-between gap-3">
          <h1 class="wt-logo">Wheel<span>ther</span></h1>
          <LinkTo @route="help" class="wt-help-link">How it works</LinkTo>
        </div>
        <p class="wt-help-lede">What the weather usually does along your bike
          route, day by day. Pick where you ride.</p>
      </header>

      <figure class="wt-world">
        <svg
          viewBox="0 7 360 141"
          role="group"
          aria-label="World map: pick a continent"
        >
          <path d={{this.other}} class="wt-world-other" aria-hidden="true" />
          {{#each this.shapes key="id" as |s|}}
            <a
              href={{s.href}}
              aria-label={{s.name}}
              class="wt-world-link {{if (this.isHovered s.id) 'is-hovered'}}"
              data-continent={{s.id}}
              {{on "click" (fn this.open s.id)}}
              {{on "mouseenter" (fn this.hover s.id)}}
              {{on "mouseleave" (fn this.hover undefined)}}
              {{on "focus" (fn this.hover s.id)}}
              {{on "blur" (fn this.hover undefined)}}
            >
              <title>{{s.name}}</title>
              <path d={{s.d}} />
            </a>
          {{/each}}
        </svg>
        <figcaption class="wt-world-caption" aria-live="polite">
          {{if this.caption this.caption "Click a continent"}}
        </figcaption>
      </figure>

      <nav class="wt-world-list" aria-label="Continents">
        {{#each this.shapes as |s|}}
          <LinkTo @route="continent" @model={{s.id}}>{{s.name}}</LinkTo>
        {{/each}}
      </nav>
    </div>
  </template>
}
