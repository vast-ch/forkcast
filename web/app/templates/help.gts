import Component from '@glimmer/component';
import { service } from '@ember/service';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';
import type AtlasService from 'forkcast/services/atlas';
import { rainyDays } from 'forkcast/utils/climate';
import Logo from 'forkcast/components/logo';

/** Worked example for the rainy-day estimate: a month with 60 mm on 12 wet days. */
const EXAMPLE = [1, 5, 10].map((t) => ({
  t,
  days: rainyDays(60, 12, t).toFixed(1),
}));

export default class Help extends Component {
  @service declare atlas: AtlasService;

  example = EXAMPLE;

  get years() {
    const y = this.atlas.climate?.years;
    return y ? `${y[0]}–${y[1]}` : '2011–2025';
  }

  get routeCount() {
    return this.atlas.continents
      .flatMap((c) => c.routes)
      .filter((r) => r.group === 'EuroVelo').length;
  }

  <template>
    {{pageTitle "How it works · Forkcast"}}
    <div class="wt-help-page">
      <header class="wt-help-header">
        {{#if this.atlas.continent}}
          <LinkTo
            @route="continent"
            @model={{this.atlas.continent.id}}
            class="wt-help-link"
          >← Back to the map</LinkTo>
        {{else}}
          <LinkTo @route="index" class="wt-help-link">← Back to the map</LinkTo>
        {{/if}}
        <h1 class="wt-logo-heading mt-3"><LinkTo
            @route="index"
            aria-label="Forkcast home"
          ><Logo /></LinkTo></h1>
        <p class="wt-help-lede">What the weather usually does along your bike
          route, day by day. Here is where the numbers come from, how they are
          calculated, and how far to trust them.</p>
      </header>

      <nav class="wt-help-toc" aria-label="On this page">
        <a href="#map">The map</a>
        <a href="#data">Where the data comes from</a>
        <a href="#maths">How it is calculated</a>
        <a href="#precision">How precise it is</a>
        <a href="#trip">Trip and days</a>
        <a href="#links">Bookmarks</a>
        <a href="#routes">Routes</a>
        <a href="#sources">Sources and licences</a>
      </nav>

      <article class="wt-help">
        <section id="map">
          <h2>The map</h2>
          <p>
            Colour shows the average
            <strong>day high</strong>
            (or
            <strong>night low</strong>) for the chosen month. Dots show rain on
            top of it: the dot's area grows with the month's rainfall, or with
            the number of rainy days if you switch to that. When you zoom out,
            neighbouring dots merge into one showing their average, so they stay
            readable. Point at the map to read the averages for that spot; point
            at your route to see the day you would be there and the weather
            expected on that date.
          </p>
        </section>

        <section id="data">
          <h2>Where the weather data comes from</h2>
          <p>
            The climate numbers come from
            <strong>CRU TS 4.10</strong>, published by the Climatic Research
            Unit of the University of East Anglia. It is built from the monthly
            records of thousands of weather stations, interpolated onto a
            regular grid of 0.5° by 0.5° over land. For every grid cell and
            every month since 1901 it gives the average daily maximum and
            minimum temperature, the month's precipitation and the number of wet
            days (days with at least 0.1 mm).
          </p>
          <p>
            Forkcast takes the
            {{this.years}}
            part of it, 15 years, and averages each calendar month over those
            years: every January value on the map is the mean of 15 Januaries.
            That is a "climate normal": what a typical year looks like, recent
            enough to include most of today's warming. The result is cut into
            one file per continent and stored compactly (temperatures to 0.1 °C,
            rain to 1 mm, wet days to 0.1 day), so opening a continent downloads
            well under 2 MB.
          </p>
        </section>

        <section id="maths">
          <h2>How it is calculated</h2>
          <dl class="wt-help-defs">
            <div><dt>Between grid cells</dt><dd>A place's value is a weighted
                average of the four surrounding cell centres (bilinear
                interpolation), with weights by distance. Over the sea there is
                no data; a point near the coast uses only the land cells next to
                it.</dd></div>
            <div><dt>Between months</dt><dd>Each month's average is treated as
                the value in the middle of that month. A date in between is
                blended linearly: on 1 February the January and February values
                count about half each.</dd></div>
            <div><dt>Day high, night low</dt><dd>The high for a riding day is
                taken at the middle of that day's stretch; the night low at the
                end of it, where you sleep.</dd></div>
            <div><dt>Rain per day</dt><dd>The month's rainfall divided by its
                number of days.</dd></div>
            <div><dt>Rainy days</dt><dd>Estimated from rainfall and wet days
                (see below), then divided by the month's length to give the
                chance that a given day is rainy.</dd></div>
            <div><dt>Rainy riding days</dt><dd>The sum of those chances over all
                riding days: the expected number, not a promise.</dd></div>
          </dl>
          <p>
            <strong>The rainy-day estimate.</strong>
            The records only count days with at least 0.1 mm, so a five-minute
            drizzle counts. To get days over 1, 5 or 10 mm, Forkcast assumes
            that rain amounts on wet days follow an exponential distribution, a
            standard model for daily rainfall. Its mean is the month's total
            divided by its wet days, and the share of wet days reaching a
            threshold
            <em>T</em>
            is then exp(−(<em>T</em>
            − 0.1) ÷ mean). For a month with 60 mm on 12 wet days (5 mm per wet
            day on average):
          </p>
          <table class="wt-help-table">
            <thead><tr><th>Rainy day</th><th>Days in the month</th></tr></thead>
            <tbody>
              {{#each this.example as |row|}}
                <tr><td>over {{row.t}} mm</td><td>{{row.days}}</td></tr>
              {{/each}}
            </tbody>
          </table>
          <p>
            Over 1 mm is the meteorological rain day; over 5 mm, the default, is
            a proper wet day with rain gear on; over 10 mm is a soaking.
          </p>
        </section>

        <section id="precision">
          <h2>How precise it is</h2>
          <p>
            The numbers are averages, and the biggest uncertainty is not in the
            maths but in the weather itself. Measured in the same 15 years of
            data:
          </p>
          <ul>
            <li><strong>Year to year,</strong>
              a month's average high in Europe typically varies by ±1.3 to ±1.7
              °C (one standard deviation); more in continental winters (Kraków
              in January ±2.1 °C, between −2.7 and 3.8 °C) and less on the
              Mediterranean (Valencia in January ±0.9 °C).</li>
            <li><strong>Day to day</strong>
              the spread is far larger. The data is monthly so it cannot show
              this, but as a rule of thumb single days often sit 4–6 °C above or
              below the average. Read the numbers as "what to pack for", not
              "what it will be".</li>
            <li><strong>Rain varies most:</strong>
              a month's rainfall typically differs from its average by about a
              third (Interlaken in January: 92 mm on average, ±44 mm). Rainy-day
              counts carry that uncertainty, plus the estimate's own: the
              estimate is most reliable over 1 mm and least reliable over 10 mm,
              where the exponential model fits heavy downpours worst.</li>
          </ul>
          <p><strong>Limits of the grid and the maths:</strong></p>
          <ul>
            <li><strong>Resolution.</strong>
              A cell is about 55 km north to south and 55 km × cos(latitude)
              east to west (about 39 km at 45° N). Anything smaller (a valley, a
              lakeshore, a narrow coast) is averaged with its surroundings.
              Coastal towns therefore often read colder by day and wetter than
              they are: Nice in January shows about 10 °C where the city
              averages nearer 13 °C.</li>
            <li><strong>Altitude is not corrected.</strong>
              A cell stands for its average height. Air cools about 6.5 °C per
              1,000 m of climb, so a pass 1,000 m above its surroundings is
              roughly that much colder than the map says.</li>
            <li><strong>Few stations, more error.</strong>
              Where stations are sparse (deserts, Siberia, high mountains, parts
              of Africa and South America) the grid is interpolated over long
              distances and can be off by more.</li>
            <li><strong>Blending between months</strong>
              is linear; the real seasonal curve is smooth, so near the turn of
              a month the value can be off by a few tenths of a degree, rarely
              more than 0.5 °C.</li>
            <li><strong>Warming.</strong>
              The 15-year average is centred on 2018. In Europe temperatures
              have risen by roughly 0.5 °C per decade, so this year's normal is
              likely a few tenths warmer than shown.</li>
            <li><strong>Distances and climbing</strong>
              are measured along the route's points. Simplified tracks lose
              small bumps, so climbing tends to come out somewhat low; drawn
              routes are straight lines between your clicks and have no
              elevation.</li>
          </ul>
          <p>
            The stored values (0.1 °C, 1 mm) are far finer than any of this, so
            the app rounds what it shows: whole degrees, whole percent.
          </p>
        </section>

        <section id="trip">
          <h2>Trip and days</h2>
          <p>
            The trip starts on your start date and covers the route at your km
            per day. Ride days and rest days form a repeating pattern: ride 5,
            rest 2 means five riding days, two rest days, then again. A trip
            never ends on a rest day.
          </p>
          <ul>
            <li>A riding day's
              <strong>high</strong>
              and
              <strong>rain</strong>
              are taken at the middle of that day's stretch.</li>
            <li>The
              <strong>night</strong>
              low is taken where you sleep, at the end of the day's stretch.</li>
            <li>Values for a date are blended between monthly averages: each
              month's average counts as its middle, so 31 January is about
              halfway between January and February.</li>
            <li><strong>Climbing</strong>
              adds up every ascent along the day's stretch, from the route's
              elevation data.</li>
          </ul>
          <p>
            In the chart, each bar runs from the night low to the day high and
            is coloured by the high. The blue bar underneath is the chance of a
            rainy day. Shaded columns are rest days. Click a day, in the chart
            or in the day list, to show its stretch on the map.
          </p>
        </section>

        <section id="links">
          <h2>Bookmarks and sharing</h2>
          <p>
            Everything you set (continent, month, layers, route, start date,
            distances, rest pattern, the highlighted day and your own route) is
            kept in the page address. Bookmark it or send the link, and the same
            plan opens again. Settings left at their defaults are not written to
            the address, so links stay short.
          </p>
        </section>

        <section id="routes">
          <h2>Routes</h2>
          <p>
            All
            {{this.routeCount}}
            EuroVelo routes come from the official EuroVelo GPX tracks. Where
            the official track offers variants, such as both banks of a river or
            alternatives through different countries, Forkcast follows the
            shortest path from start to finish. Ferries count as travel time but
            not as riding distance.
          </p>
          <p>
            The demo route, Interlaken – Málaga, runs down the Rhône valley and
            Spain's east coast. It was routed for touring bikes along
            cycle-friendly roads.
          </p>
          <p>
            Your own route can be drawn on the map (points joined with straight
            lines) or imported from a GPX file. It is kept in the page address,
            simplified to at most 600 points, so a bookmark brings it back.
            Drawing or importing another one replaces it. "Export GPX" saves the
            selected route as a file.
          </p>
        </section>

        <section id="sources">
          <h2>Sources and licences</h2>
          <ul>
            <li>
              <strong>Climate:</strong>
              <a
                href="https://crudata.uea.ac.uk/cru/data/hrg/"
                target="_blank"
                rel="noopener noreferrer"
              >CRU TS 4.10</a>, Climatic Research Unit, University of East
              Anglia: monthly mean daily maximum and minimum temperature,
              precipitation and wet days, averaged over
              {{this.years}}.
            </li>
            <li>
              <strong>EuroVelo routes:</strong>
              contains information from EuroVelo GPX tracks downloaded from
              <a
                href="https://www.eurovelo.com"
                target="_blank"
                rel="noopener noreferrer"
              >www.EuroVelo.com</a>
              on 2026-10-23, which is made available here under the
              <a
                href="https://opendatacommons.org/licenses/odbl/1-0/"
                target="_blank"
                rel="noopener noreferrer"
              >Open Database License (ODbL)</a>. EuroVelo® is a registered
              trademark of the European Cyclists' Federation.
            </li>
            <li>
              <strong>Demo route:</strong>
              routed with
              <a
                href="https://brouter.de"
                target="_blank"
                rel="noopener noreferrer"
              >BRouter</a>
              on ©
              <a
                href="https://www.openstreetmap.org/copyright"
                target="_blank"
                rel="noopener noreferrer"
              >OpenStreetMap</a>
              contributors data (ODbL).
            </li>
            <li>
              <strong>Borders:</strong>
              <a
                href="https://www.naturalearthdata.com"
                target="_blank"
                rel="noopener noreferrer"
              >Natural Earth</a>, public domain.
            </li>
          </ul>
        </section>
      </article>
    </div>
  </template>
}
