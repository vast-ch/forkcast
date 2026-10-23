import type { TOC } from '@ember/component/template-only';

/**
 * The Forkcast logo: a bicycle wheel rising over the horizon like the sun,
 * followed by the wordmark. Same drawing as public/logo.svg and the favicons.
 */
const Logo: TOC<{ Element: HTMLSpanElement }> = <template>
  <span class="wt-logo" ...attributes>
    <svg viewBox="1 18 62 28.5" class="wt-logo-mark" aria-hidden="true">
      <path d="M12 44a20 20 0 0 1 40 0z" class="wt-logo-sun" /><g
        fill="none"
        class="wt-logo-ink"
      ><path
          d="M36.0 44.0L47.8 31.7M48.2 44.0L52.0 43.3M25.9 44.0L13.2 37.2M28.2 42.8L20.8 27.4M28.8 41.6L15.8 44.0M29.6 40.8L32.7 24.0M30.8 40.2L15.4 32.8M32.0 40.0L44.3 28.2M33.2 40.2L25.2 25.2M34.4 40.8L51.2 38.5M35.2 41.6L37.5 24.8M35.8 42.8L38.1 44.0"
          stroke-width="1.3"
        /><path d="M12 44a20 20 0 0 1 40 0" stroke-width="1.4" /><path
          d="M10 44a22 22 0 0 1 44 0"
          stroke-width="4.5"
        /><path d="M4 44h56" stroke-width="5" stroke-linecap="round" /></g>
    </svg>
    <span>Fork<span class="wt-logo-cast">cast</span></span>
  </span>
</template>;

export default Logo;
