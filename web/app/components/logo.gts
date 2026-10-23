import type { TOC } from '@ember/component/template-only';

/**
 * The Forkcast logo: a bicycle fork with the sun between its legs (fork +
 * forecast), followed by the wordmark. Same drawing as public/logo.svg.
 */
const Logo: TOC<{ Element: HTMLSpanElement }> = <template>
  <span class="wt-logo" ...attributes>
    <svg viewBox="0 0 64 64" class="wt-logo-mark" aria-hidden="true">
      <circle cx="32" cy="41" r="9" class="wt-logo-sun" />
      <g
        fill="none"
        class="wt-logo-fork"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <path d="M32 6v15" stroke-width="7" />
        <path d="M17 58c-1-12 0-25 3-35h24c3 10 4 23 3 35" stroke-width="6.5" />
      </g>
    </svg>
    <span>Fork<span class="wt-logo-cast">cast</span></span>
  </span>
</template>;

export default Logo;
