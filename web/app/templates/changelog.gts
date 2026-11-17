import { LinkTo } from '@ember/routing';
import { htmlSafe } from '@ember/template';
import { pageTitle } from 'ember-page-title';
import Logo from 'forkcast/components/logo';
import type { TOC } from '@ember/component/template-only';
import { helpColumn, helpLink, prose } from 'forkcast/utils/classes';

// The HTML is our own changelog's (see routes/changelog.ts), so it's trusted.
const Changelog: TOC<{ Args: { model: string } }> = <template>
  {{pageTitle "What's new"}}
  <div class="h-full overflow-y-auto px-5 pt-8 pb-16">
    <header class={{helpColumn}}>
      <LinkTo @route="index" class="wt-help-link {{helpLink}}">← Back to the map</LinkTo>
      <h1 class="mt-3"><LinkTo @route="index" aria-label="Forkcast home"><Logo
          /></LinkTo></h1>
      <p class="mt-3 text-[1.1rem] text-balance text-wt-muted">What's new in
        Forkcast, release by release.</p>
    </header>
    <article class="wt-changelog {{prose}}">
      {{htmlSafe @model}}
    </article>
  </div>
</template>;

export default Changelog;
