import type { TOC } from '@ember/component/template-only';
import Measured from 'forkcast/components/help/measured';
import AltitudeDemo from 'forkcast/components/help/altitude-demo';
import { LAPSE_RATES } from 'forkcast/utils/climate';
import { signed, value } from 'forkcast/utils/verify';

const MONTHS = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(' ');
const LAPSE = LAPSE_RATES.map((r, i) => ({
  month: MONTHS[i],
  perKm: (r * 1000).toFixed(1),
}));

const CURVE = [
  { field: 'tmx', label: 'Highs' },
  { field: 'tmn', label: 'Lows' },
  { field: 'pre', label: 'Rain, a month' },
  { field: 'r5', label: 'Rainy days (5 mm), a month' },
];

/** The Data tab in Nerd mode: the sources, every step from them to a number, and what each step loses. */
const NerdData: TOC<{ Args: { years: string } }> = <template>
  <section id="data">
    <h2>Where the numbers come from</h2>

    <h3>Sources</h3>
    <dl class="wt-help-defs">
      <div><dt>ERA5-Land</dt><dd>ECMWF's land reanalysis for Copernicus, 0.1°,
          hourly, regridded to 0.25° for Forkcast: daily rain totals (the 00:00
          step holds the day before), the monthly average temperature by hour of
          day, and terrain height.</dd></div>
      <div><dt>CRU TS 4.10</dt><dd>Station-based monthly mean daily maximum and
          minimum, 0.5°, from the Climatic Research Unit.</dd></div>
      <div><dt>NOAA CPC</dt><dd>CPC Global Unified Temperature: station-based
          daily maximum and minimum, 0.5°.</dd></div>
    </dl>

    <h3>From the sources to a grid</h3>
    <ol>
      <li><strong>Rain:</strong>
        each day of
        {{@years}}
        summed into its month, and counted against 1, 5 and 10 mm; the monthly
        grid holds the average month.</li>
      <li><strong>Highs and lows:</strong>
        ERA5-Land's average day for each month peaks lower than the average of
        single days' highs (days peak at different hours) and bottoms out higher
        than their lows. So the warmest and coldest hour are shifted to CRU's
        means: the offset between them is worked out on CRU's 0.5° cells,
        smoothed and interpolated to 0.25° (cells without CRU take their nearest
        neighbours'), which keeps ERA5-Land's detail and CRU's level.</li>
      <li><strong>The grid:</strong>
        84° N to 60° S, 0.25°, one byte a value (highs and lows in 0.5 °C steps,
        rain on a square-root scale), 12 months a layer.</li>
    </ol>

    <h3>From the grid to the app: seasonal curves</h3>
    <p>
      Each cell's 12 months become a curve: the mean plus three yearly waves
      (12, 6 and 4 months), 7 numbers. A month's average flattens the k-th wave
      by sin(πk/12)/(πk/12), so the fit scales the waves back up; the curve's
      average over each month then matches the month as closely as three waves
      can. Rain is fitted per day (a month's total over its length). Each number
      is stored in a byte with its own scale, rain's waves as a share of the
      cell's mean so dry places keep their precision, in 10° tiles of 41 × 41
      cells sharing their edges.
    </p>
    <p>
      A point's value is the bilinear average of its four cells, sea cells left
      out (so the coast still gets a value; just off it, the nearest land cell
      within two). A day's value is the curve at that day's place in the year.
    </p>

    <h3>Altitude</h3>
    <p>
      On a route, highs and lows get −Γ × (point's height − cell's mean height),
      with Γ the month's lapse rate across the Alps (Rolland 2003), blended
      between mid-months, in °C per 1,000 m:
    </p>
    <table class="wt-help-table">
      <thead><tr>{{#each LAPSE as |l|}}<th
              scope="col"
            >{{l.month}}</th>{{/each}}</tr></thead>
      <tbody><tr>{{#each LAPSE as |l|}}<td
            >{{l.perKm}}</td>{{/each}}</tr></tbody>
    </table>
    <AltitudeDemo />

    <h3>What each step changes, measured</h3>
    <Measured as |m|>
      <p>
        The CRU calibration moves Europe's average month, over land, by
        {{signed m "calibration" "tmx" "Europe" "least month"}}
        to
        {{signed m "calibration" "tmx" "Europe" "most month"}}
        for highs and
        {{signed m "calibration" "tmn" "Europe" "least month"}}
        to
        {{signed m "calibration" "tmn" "Europe" "most month"}}
        for lows: ERA5-Land's warmest hour is cooler than the stations' average
        high, and its coldest hour is a bit warmer than their average low.
      </p>
      <table class="wt-help-table">
        <caption>The seasonal curve against the monthly grid, every land cell
          and month: the fit alone, and as the app gets it (packed in bytes)</caption>
        <thead><tr><th scope="col"></th><th scope="col">Typical (mean)</th><th
              scope="col"
            >1 in 20 worse than (95th percentile)</th><th scope="col">Packed,
              typical</th><th scope="col">Packed, 95th</th></tr></thead>
        <tbody>
          {{#each CURVE as |c|}}
            <tr><th scope="row">{{c.label}}, Europe</th>
              <td>{{value m "curve-fit" c.field "Europe" "mae"}}</td>
              <td>{{value m "curve-fit" c.field "Europe" "p95"}}</td>
              <td>{{value m "curve-packed" c.field "Europe" "mae"}}</td>
              <td>{{value m "curve-packed" c.field "Europe" "p95"}}</td></tr>
          {{/each}}
          {{#each CURVE as |c|}}
            <tr><th scope="row">{{c.label}}, world</th>
              <td>{{value m "curve-fit" c.field "World" "mae"}}</td>
              <td>{{value m "curve-fit" c.field "World" "p95"}}</td>
              <td>{{value m "curve-packed" c.field "World" "mae"}}</td>
              <td>{{value m "curve-packed" c.field "World" "p95"}}</td></tr>
          {{/each}}
        </tbody>
      </table>
      <p>
        This covers every land cell, so there's no sampling error: the numbers
        are what three waves and one byte each lose. The curve misses most where
        the seasons turn fast (a monsoon's onset), which no smooth curve can
        follow; packing adds a little on top.
      </p>
    </Measured>
  </section>
</template>;

export default NerdData;
