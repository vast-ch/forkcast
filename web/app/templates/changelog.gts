import { LinkTo } from '@ember/routing';
import { htmlSafe } from '@ember/template';
import { pageTitle } from 'ember-page-title';
import Logo from 'forkcast/components/logo';
import type { TOC } from '@ember/component/template-only';

// The HTML is our own changelog's (see routes/changelog.ts), so it's trusted.
const Changelog: TOC<{ Args: { model: string } }> = <template>
  {{pageTitle "What's new"}}
  <div class="wt-help-page">
    <header class="wt-help-header">
      <LinkTo @route="index" class="wt-help-link">← Back to the map</LinkTo>
      <h1 class="wt-logo-heading mt-3"><LinkTo
          @route="index"
          aria-label="Forkcast home"
        ><Logo /></LinkTo></h1>
      <p class="wt-help-lede">What's new in Forkcast, release by release.</p>
    </header>
    <article class="wt-help wt-changelog">
      {{htmlSafe @model}}
    </article>
  </div>
</template>;

export default Changelog;
