import type { TOC } from '@ember/component/template-only';
import Measured from 'forkcast/components/help/measured';
import { RAIN_THRESHOLDS, TEMP_STOPS } from 'forkcast/utils/climate';
import { DOT_FULL, rainEmojiTiers } from 'forkcast/utils/layers';
import { css } from 'forkcast/utils/format';
import { value } from 'forkcast/utils/verify';

const STOPS = TEMP_STOPS.map(([t, color]) => ({
  t: String(t).replace('-', '−'),
  swatch: css('background: ', color),
  color,
}));

const EMOJI = RAIN_THRESHOLDS.map((mm) => ({
  mm,
  tiers: rainEmojiTiers(mm),
}));

/** The Map tab in Nerd mode: how each layer is drawn from the curves. */
const NerdMap: TOC<object> = <template>
  <section id="map">
    <h2>The map</h2>
    <p>
      Every layer is drawn from the climate's seasonal curves (see Data) at the
      start of the week shown: one of 48 quarter-months, 7 or 8 days each, so
      four per month and lined up with the months.
    </p>

    <h3>Temperature</h3>
    <p>
      The high (or low) of each 0.25° cell, interpolated linearly between these
      stops and flat beyond the ends, drawn onto a Web-Mercator canvas of about
      3 pixels per cell (at most 12 per degree), transparent over the sea:
    </p>
    <table class="wt-help-table">
      <thead><tr><th scope="col">°C</th>{{#each STOPS as |s|}}<th
              scope="col"
            >{{s.t}}</th>{{/each}}</tr></thead>
      <tbody><tr><th scope="row">Colour</th>{{#each STOPS as |s|}}<td><span
                class="wt-help-swatch"
                style={{s.swatch}}
                title={{s.color}}
              ></span></td>{{/each}}</tr></tbody>
    </table>
    <p>
      The relief shading is lit from the north-west, 45° up, on ERA5-Land's
      terrain, with heights exaggerated 10 times, and darkens slopes facing away
      by up to three quarters.
    </p>

    <h3>Rain</h3>
    <ul>
      <li><strong>Emoji:</strong>
        the rainy-day chance at the chosen threshold × 7, as rainy days a week;
        the steps differ by threshold because heavier rain is rarer:
        <dl class="wt-help-defs">
          {{#each EMOJI as |e|}}
            <div><dt>{{e.mm}} mm</dt><dd>
                {{#each e.tiers as |t|}}
                  <span class="wt-help-rain-step">{{t.emoji}}
                    from
                    {{t.min}}</span>
                {{/each}}
              </dd></div>
          {{/each}}
        </dl></li>
      <li><strong>Dots:</strong>
        one per cell, its area proportional to the rain (or the rainy-day
        chance) scaled to an average month, filling the cell at
        {{DOT_FULL.mm}}
        mm (or
        {{DOT_FULL.days}}
        rainy days), at most 1.3 times that, and 85% of the cell's width so
        neighbours don't touch. Sized in metres, so they keep their size against
        the land.</li>
      <li><strong>Zoomed out,</strong>
        emoji and dots stay at least 30 and 9 pixels apart by merging square
        blocks of cells into one, showing their average. Blocks line up with the
        world's grid, not a tile's corner, so neighbouring tiles merge alike.</li>
    </ul>

    <h3>Tiles</h3>
    <p>
      The climate comes in 10° squares (41 × 41 cells, sharing their edges so a
      point anywhere in one is interpolated from it alone). The squares a route
      crosses load with it; any other loads on a click. Pointing at the map
      reads the point's value from its square.
    </p>

    <h3>Cities</h3>
    <p>
      “10 biggest” is the 10 biggest towns per country, “500k+” every town of at
      least 500,000 people, from Natural Earth; below zoom 6 only capitals keep
      their names.
    </p>

    <h3>How exact the colours are</h3>
    <Measured as |m|>
      <p>
        A colour is the curve, not the month it was fitted to. Against Europe's
        monthly grid the curve as packed is off by
        {{value m "curve-packed" "tmx" "Europe" "mae"}}
        for a typical cell and month and by more than
        {{value m "curve-packed" "tmx" "Europe" "p95"}}
        in 1 in 20; rainy days at 5 mm by
        {{value m "curve-packed" "r5" "Europe" "mae"}}
        a month. A colour stop is 5 °C apart, so that's a small fraction of a
        step. The Data tab has the whole table.
      </p>
    </Measured>
  </section>
</template>;

export default NerdMap;
