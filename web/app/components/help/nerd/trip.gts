import type { TOC } from '@ember/component/template-only';
import Measured from 'forkcast/components/help/measured';
import { value, withInterval } from 'forkcast/utils/verify';

/** The Trip tab in Nerd mode: how a day's and a trip's numbers are made, and how they hold up against real days. */
const NerdTrip: TOC<object> = <template>
  <section id="trip">
    <h2>Your trip</h2>

    <h3>Days</h3>
    <p>
      The route is cut into riding days of “km per day” (the last one shorter),
      with rest days inserted by the ride/rest pattern; a trip never ends on a
      rest day. Each day is sampled on the route:
    </p>
    <ul>
      <li><strong>Low:</strong>
        at the day's night stop, where it ends (on a rest day, where you stay),
        on that date.</li>
      <li><strong>High, rain:</strong>
        at the middle of the day's stretch, by distance, on that date.</li>
      <li><strong>Altitude:</strong>
        both get the altitude correction for the point's height against its grid
        cell's (see Data).</li>
      <li><strong>Climbing:</strong>
        every rise between the route's points added up, on the track as built
        (simplified to 30–40 m).</li>
      <li><strong>Daylight:</strong>
        sunrise where the day starts to sunset where it ends, from the sun's
        position (NOAA's formulas); the app's tests hold it within 3 minutes of
        published tables.</li>
    </ul>

    <h3>The usual range</h3>
    <p>
      For a day's high: mean ± 1.28 σ, where σ is how far single days' highs
      stray from their average at that place and time of year (a standard
      deviation, from NOAA CPC's daily station data 2011–2025: each day's
      departure from its cell's seasonal curve, per month). For a normal
      distribution, 80% of days fall within ± 1.28 σ, 10% below and 10% above.
      The same for lows.
    </p>

    <h3>Likely lowest low, likely highest high</h3>
    <p>
      The value x the trip is as likely to beat as not. With each day's low
      normal (mean μᵢ, spread σᵢ), the chance that no night goes below x is ∏
      Φ((μᵢ − x) / σᵢ). Cold comes in spells, so neighbouring nights aren't
      independent tries: the app counts one try per 2 nights (2.5 days for
      highs), solving ∏ Φ(…)^(1/2) = ½ for x by bisection. Over a single day it
      is that day's average.
    </p>

    <h3>Rainy days and their range</h3>
    <p>
      The expected count is the days' chances added up. The range is where 8
      trips in 10 fall: the count as beta-binomial with the days' average chance
      p, its variance widened from that of independent days (Σ pᵢ(1 − pᵢ)) by a
      spell factor of 2 at 1 mm, 1.6 at 5 mm and 1.5 at 10 mm (heavier rain
      clusters less), then cut at 10% and 90%.
    </p>

    <h3>How it holds up</h3>
    <Measured as |m|>
      <p>
        Measured on real days, at random land places:
        {{value m "sample" "" "World" "places"}}
        over the world and
        {{value m "sample" "" "Europe" "places"}}
        in Europe (drawn by area, where CPC has stations), the app's curves as
        the app gets them are compared with every day of 2011–2025, and on
        random trips of 7 to 60 days,
        {{value m "sample" "" "" "trips per place"}}
        per place. Places are the sample unit: a place's days share its weather,
        but random places are far apart. Each share has a 95% interval from
        resampling the places.
      </p>

      <table class="wt-help-table">
        <caption>Station days outside the usual range (10% each side if right)</caption>
        <thead><tr><th scope="col"></th><th scope="col">Below</th><th
              scope="col"
            >Above</th><th scope="col">Stations minus ours</th></tr></thead>
        <tbody>
          <tr><th scope="row">Highs, Europe</th>
            <td>{{withInterval m "range" "tmx" "Europe" "below"}}</td>
            <td>{{withInterval m "range" "tmx" "Europe" "above"}}</td>
            <td>{{withInterval m "range" "tmx" "Europe" "bias"}}</td></tr>
          <tr><th scope="row">Lows, Europe</th>
            <td>{{withInterval m "range" "tmn" "Europe" "below"}}</td>
            <td>{{withInterval m "range" "tmn" "Europe" "above"}}</td>
            <td>{{withInterval m "range" "tmn" "Europe" "bias"}}</td></tr>
          <tr><th scope="row">Highs, world</th>
            <td>{{withInterval m "range" "tmx" "World" "below"}}</td>
            <td>{{withInterval m "range" "tmx" "World" "above"}}</td>
            <td>{{withInterval m "range" "tmx" "World" "bias"}}</td></tr>
          <tr><th scope="row">Lows, world</th>
            <td>{{withInterval m "range" "tmn" "World" "below"}}</td>
            <td>{{withInterval m "range" "tmn" "World" "above"}}</td>
            <td>{{withInterval m "range" "tmn" "World" "bias"}}</td></tr>
        </tbody>
      </table>
      <p>
        The spread was measured on these same station days, so this tests the
        shape (are days close enough to normal?) and our averages against the
        stations', not the spread on unseen days. Where the averages are off,
        the range is off with them: the last column is how much warmer the
        stations' days are than our average. CPC's 0.5° grid is itself an
        interpolation between stations, so part of the difference is CPC's.
      </p>

      <table class="wt-help-table">
        <caption>Real trips beating the likely lowest low and highest high (50%
          if right)</caption>
        <thead><tr><th scope="col"></th><th scope="col">Spells counted (the app)</th><th
              scope="col"
            >Every day a try</th></tr></thead>
        <tbody>
          <tr><th scope="row">Lowest low, Europe</th>
            <td>{{withInterval m "extremes" "tmn" "Europe" "beaten"}}</td>
            <td>{{withInterval
                m
                "extremes"
                "tmn"
                "Europe"
                "beaten, every day a try"
              }}</td></tr>
          <tr><th scope="row">Highest high, Europe</th>
            <td>{{withInterval m "extremes" "tmx" "Europe" "beaten"}}</td>
            <td>{{withInterval
                m
                "extremes"
                "tmx"
                "Europe"
                "beaten, every day a try"
              }}</td></tr>
          <tr><th scope="row">Lowest low, world</th>
            <td>{{withInterval m "extremes" "tmn" "World" "beaten"}}</td>
            <td>{{withInterval
                m
                "extremes"
                "tmn"
                "World"
                "beaten, every day a try"
              }}</td></tr>
          <tr><th scope="row">Highest high, world</th>
            <td>{{withInterval m "extremes" "tmx" "World" "beaten"}}</td>
            <td>{{withInterval
                m
                "extremes"
                "tmx"
                "World"
                "beaten, every day a try"
              }}</td></tr>
        </tbody>
      </table>
      <p>
        Counting every day as its own try would put the likely extreme too far
        out, so too few trips beat it; counting spells brings it close. What
        remains off follows the averages: where our lows run colder than the
        stations', fewer trips beat the likely lowest low.
      </p>

      <table class="wt-help-table">
        <caption>Real trips outside the rainy-day range (10% each side if
          right), and the real count minus the expected one, per trip</caption>
        <thead><tr><th scope="col"></th><th scope="col">Fewer</th><th
              scope="col"
            >More</th><th scope="col">Real minus expected</th></tr></thead>
        <tbody>
          {{#each RAIN as |r|}}
            <tr><th scope="row">{{r.label}}, Europe</th>
              <td>{{withInterval m "rainy" r.field "Europe" "below"}}</td>
              <td>{{withInterval m "rainy" r.field "Europe" "above"}}</td>
              <td>{{withInterval
                  m
                  "rainy"
                  r.field
                  "Europe"
                  "real minus expected"
                }}</td></tr>
          {{/each}}
          {{#each RAIN as |r|}}
            <tr><th scope="row">{{r.label}}, world</th>
              <td>{{withInterval m "rainy" r.field "World" "below"}}</td>
              <td>{{withInterval m "rainy" r.field "World" "above"}}</td>
              <td>{{withInterval
                  m
                  "rainy"
                  r.field
                  "World"
                  "real minus expected"
                }}</td></tr>
          {{/each}}
        </tbody>
      </table>
      <p>
        Real rainy days are counted on ERA5-Land's daily rain at the same cells.
        The expected count is close; where fewer than 10% fall on each side, the
        range is wider than it needs to be (the counts are whole days, so a
        range can't always cut at exactly 10%).
      </p>
    </Measured>
  </section>
</template>;

const RAIN = [
  { field: 'r1', label: '1 mm' },
  { field: 'r5', label: '5 mm' },
  { field: 'r10', label: '10 mm' },
];

export default NerdTrip;
