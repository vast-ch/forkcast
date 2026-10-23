import type { TOC } from '@ember/component/template-only';
import { LinkTo } from '@ember/routing';
import Question from 'ember-phosphor-icons/components/ph-question';

/** The question-mark link to the help page, in the sidebar and the phone bar. */
const HelpLink: TOC<{ Args: { iconClass?: string } }> = <template>
  <LinkTo
    @route="help"
    class="wt-icon-link"
    aria-label="How it works"
    title="How it works"
  ><Question
      class={{if @iconClass @iconClass "size-5"}}
      aria-hidden="true"
    /></LinkTo>
</template>;

export default HelpLink;
