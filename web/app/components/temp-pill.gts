import type { TOC } from '@ember/component/template-only';
import { Chip } from 'frontile/buttons';
import { tempInk, tempSwatch } from 'forkcast/utils/climate';
import { css, fmtTemp } from 'forkcast/utils/format';

/** A temperature as a pill in its own colour from the map's scale. */
const TempPill: TOC<{
  Args: { t: number | null | undefined };
  Element: HTMLDivElement;
}> = <template>
  <Chip
    @size="sm"
    class="wt-temp-pill"
    style={{css
      "background: "
      (tempSwatch @t "var(--wt-band)")
      "; color: "
      (tempInk @t)
    }}
    ...attributes
  >{{fmtTemp @t}}</Chip>
</template>;

export default TempPill;
