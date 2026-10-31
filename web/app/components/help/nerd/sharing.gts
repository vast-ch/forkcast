import type { TOC } from '@ember/component/template-only';
import Measured from 'forkcast/components/help/measured';
import { value } from 'forkcast/utils/verify';

/** The Sharing & privacy tab in Nerd mode: exactly what is stored where, and what is fetched when. */
const NerdSharing: TOC<object> = <template>
  <section id="sharing">
    <h2>Sharing and privacy</h2>

    <h3>Where things are kept</h3>
    <dl class="wt-help-defs">
      <div><dt>The address</dt><dd>Every planner setting is a query parameter,
          left out at its default; values that don't parse read as the default.
          Your own route appears only as a random UUID.</dd></div>
      <div><dt>This browser</dt><dd>localStorage holds your routes (whole
          tracks, polyline-encoded with heights, plus a drawn route's clicks),
          your last plan's query string and the map's view. Nothing in it is
          ever sent.</dd></div>
      <div><dt>A server</dt><dd>None. The site is static files on Netlify.</dd></div>
    </dl>

    <h3>What your browser fetches</h3>
    <ul>
      <li><strong>The app:</strong>
        its code, styles and fonts, from the site itself.</li>
      <li><strong>Always:</strong>
        the route list, the world's borders and the climate's header.</li>
      <li><strong>When needed:</strong>
        a route's track when you pick it; city names, rivers and lakes when
        switched on; the cycle network when you draw with “Follow cycle routes”.</li>
      <li><strong>Climate squares:</strong>
        those your route crosses, and those you click. This is the one thing
        that says where on Earth you looked: the host's logs could show which
        squares were fetched, not your route, dates or anything else.</li>
    </ul>
    <Measured as |m|>
      <p>
        The default climate has
        {{value m "size" "tiles" "World" "count"}}
        squares with land,
        {{value m "size" "tiles" "World" "all MB"}}
        in all; a square is typically
        {{value m "size" "tiles" "World" "median kB gzipped"}}
        over the wire (gzipped), at most
        {{value m "size" "tiles" "World" "largest kB gzipped"}}.
      </p>
    </Measured>

    <h3>What's refused</h3>
    <p>
      The content security policy allows code, styles, fonts, images and
      requests from the site itself only (<code>default-src 'self'</code>, no
      third-party scripts, no frames), with
      <code>Referrer-Policy: no-referrer</code>, so following a link out of the
      app sends no address, and no ad topics. Every data file has a content hash
      in its name and is cached for a year, so a returning visitor fetches only
      what changed.
    </p>
  </section>
</template>;

export default NerdSharing;
