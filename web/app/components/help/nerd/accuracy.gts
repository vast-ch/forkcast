import type { TOC } from '@ember/component/template-only';
import Measured from 'forkcast/components/help/measured';
import { signed, value, withInterval } from 'forkcast/utils/verify';

/** The Accuracy tab in Nerd mode: how much the weather itself varies, and the data's known limits, measured. */
const NerdAccuracy: TOC<{ Args: { years: string } }> = <template>
  <section id="accuracy">
    <h2>How far to trust it</h2>
    <p>
      Every number here is measured by the data pipeline's verify step; the Trip
      and Climates tabs have the tests against real days and years.
    </p>
    <Measured as |m|>
      <h3>The weather itself</h3>
      <table class="wt-help-table">
        <caption>How much a month swings from year to year,
          {{@years}}, on ERA5-Land's months (a standard deviation over the
          years)</caption>
        <tbody>
          <tr><th scope="row">Average high, Europe, typical cell</th>
            <td>{{value m "yearly" "tmx" "Europe" "median sd, least month"}}
              to
              {{value m "yearly" "tmx" "Europe" "median sd, most month"}}, by
              month (winter swings most)</td></tr>
          <tr><th scope="row">Average high, Kraków, January</th>
            <td>{{value m "yearly" "tmx" "Kraków" "sd Jan"}}</td></tr>
          <tr><th scope="row">Average high, Valencia, January</th>
            <td>{{value m "yearly" "tmx" "Valencia" "sd Jan"}}</td></tr>
          <tr><th scope="row">Rain, Europe, typical cell and month</th>
            <td>{{value m "yearly" "pre" "Europe" "median relative sd"}}
              of its average (months of 20 mm or more)</td></tr>
          <tr><th scope="row">Rain, Interlaken, January</th>
            <td>{{value m "yearly" "pre" "Interlaken" "mean Jan"}}
              on average, ±
              {{value m "yearly" "pre" "Interlaken" "sd Jan"}}</td></tr>
        </tbody>
      </table>
      <p>
        Single days stray much further: the usual range (Trip) holds 8 days in
        10, so 1 in 10 is warmer and 1 in 10 colder, and the Trip tab measures
        how well it does.
      </p>

      <h3>Warming</h3>
      <p>
        The year's average high, over land, rose by
        {{withInterval m "trend" "tmx" "Europe" "per decade"}}
        per decade in Europe and
        {{withInterval m "trend" "tmx" "World" "per decade"}}
        over the world, 1981–2025 (a straight-line fit, 95% interval). The
        default climate is centred on 2018, so a trip this year is likely a few
        tenths warmer than shown; the Climates tab measures what that lag costs.
      </p>

      <h3>Known limits</h3>
      <ul>
        <li><strong>25 km cells</strong>
          average everything inside them; the altitude correction fixes most of
          a valley's or a pass's difference, not a coast's.</li>
        <li><strong>Winter in the Alps:</strong>
          against CPC's station grid at random places in the Alps ({{value
            m
            "sample"
            ""
            "Alps"
            "places"
          }}), December to February, the stations are
          {{withInterval m "winter-bias" "tmx" "Alps" "bias"}}
          warmer for highs and
          {{withInterval m "winter-bias" "tmn" "Alps" "bias"}}
          for lows. Both intervals include 0: that few places, on a gridded
          comparison, show no measured difference either way. Whether valley
          floors come out too mild, as cold-air pooling suggests, needs station
          points, which are next (issue #20).</li>
        <li><strong>Tibetan Plateau:</strong>
          ERA5-Land's January lows there jump from 2021 on, most likely its snow
          cover:
          {{signed
            m
            "quirk"
            "tmn"
            "Tibetan Plateau"
            "Jan 2021–25 minus 2011–20"
          }}
          averaged over the plateau, up to
          {{signed
            m
            "quirk"
            "tmn"
            "Tibetan Plateau"
            "Jan 2021–25 minus 2011–20, largest cell"
          }}
          in a cell, against 2011–2020. The plateau's winters come out too mild,
          the most in 5 yrs and 1 yr.</li>
        <li><strong>Few stations</strong>
          in deserts, high mountains and parts of Africa, Asia and South America
          make CRU's and CPC's values, and so the highs, lows and ranges, less
          certain there.</li>
        <li><strong>Smooth seasons:</strong>
          three yearly waves can't turn faster than a 4-month cycle; the Data
          tab measures what the curve misses.</li>
        <li><strong>Climbing</strong>
          is counted on the simplified track (30–40 m tolerance), so it comes
          out somewhat low; not yet measured.</li>
      </ul>
      <p>
        The app rounds to whole degrees and percent: the measured uncertainty is
        far larger than a tenth.
      </p>
    </Measured>
  </section>
</template>;

export default NerdAccuracy;
