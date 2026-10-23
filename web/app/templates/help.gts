import Component from '@glimmer/component';
import { service } from '@ember/service';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';
import type AtlasService from 'wheelther/services/atlas';
import { rainyDays } from 'wheelther/utils/climate';

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
    return this.atlas.presets.filter((r) => r.group === 'EuroVelo').length;
  }

  <template>
    {{pageTitle "How it works · Wheelther"}}
    <div class="wt-help-page">
      <header class="wt-help-header">
        <LinkTo @route="index" class="wt-help-link">← Back to the map</LinkTo>
        <h1 class="wt-logo mt-3">Wheel<span>ther</span></h1>
        <p class="wt-help-lede">What the weather usually does along your bike
          route, day by day. Here is where the numbers come from and how to read
          them.</p>
      </header>

      <nav class="wt-help-toc" aria-label="On this page">
        <a href="#map">The map</a>
        <a href="#rain">Rainy days</a>
        <a href="#trip">Trip and days</a>
        <a href="#routes">Routes</a>
        <a href="#limits">Limits</a>
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
            the number of rainy days if you switch to that. Both are averages of
            {{this.years}}, so they describe a typical year rather than any
            particular one.
          </p>
          <p>
            The climate data covers land only, on a grid of 0.5° (about 50 km).
            Islands and narrow coasts therefore look blocky, and coastal places
            get values that partly reflect the hills behind them. Nice in
            January, for example, shows a day high around 10° where the city
            itself averages nearer 13°.
          </p>
          <p>
            Point at the map to read the averages for that spot. Point at your
            route to see the day you would be there and the weather expected on
            that date.
          </p>
        </section>

        <section id="rain">
          <h2>Rainy days</h2>
          <p>
            The climate records count a "wet day" as any day with at least 0.1
            mm of rain, so a five-minute drizzle counts. That says little about
            whether you will get wet on the bike, so Wheelther estimates how
            many days reach a more useful amount, which you choose:
          </p>
          <dl class="wt-help-defs">
            <div><dt>Over 1 mm</dt><dd>The meteorological rain day. Light rain
                you notice, but often just a shower.</dd></div>
            <div><dt>Over 5 mm</dt><dd>The default. A proper wet day: rain gear
                on, roads wet for hours.</dd></div>
            <div><dt>Over 10 mm</dt><dd>A soaking. The kind of day you might
                rather not ride.</dd></div>
          </dl>
          <p>
            The estimate uses the month's total rain and its wet days. Rain
            amounts on wet days are close to exponentially distributed, with the
            average being total ÷ wet days, so the share of wet days reaching a
            threshold is about exp(−(threshold − 0.1) ÷ average). For a month
            with 60 mm on 12 wet days (5 mm per wet day on average) that gives:
          </p>
          <table class="wt-help-table">
            <thead><tr><th>Threshold</th><th>Rainy days in the month</th></tr></thead>
            <tbody>
              {{#each this.example as |row|}}
                <tr><td>over {{row.t}} mm</td><td>{{row.days}}</td></tr>
              {{/each}}
            </tbody>
          </table>
          <p>
            The "chance of rain" for a day is the month's rainy days divided by
            its length. "Rainy riding days" in the trip summary adds those
            chances up over the riding days.
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
            <li>Town names next to days are the nearest stage town within 40 km.</li>
          </ul>
          <p>
            In the chart, each bar runs from the night low to the day high and
            is coloured by the high. The blue bar underneath is the chance of a
            rainy day. Shaded columns are rest days. Click a day, in the chart
            or in the day list, to show its stretch on the map.
          </p>
        </section>

        <section id="routes">
          <h2>Routes</h2>
          <p>
            All
            {{this.routeCount}}
            EuroVelo routes come from the official EuroVelo GPX tracks. Where
            the official track offers variants, such as both banks of a river or
            alternatives through different countries, Wheelther follows the
            shortest path from start to finish. Ferries count as travel time but
            not as riding distance.
          </p>
          <p>
            The demo route, Interlaken – Málaga, runs down the Rhône valley and
            Spain's east coast. It was routed for touring bikes along
            cycle-friendly roads.
          </p>
          <p>
            Your own routes can be drawn on the map (points joined with straight
            lines) or imported from a GPX file. They are saved in this browser
            only. "Export GPX" saves the selected route as a file.
          </p>
        </section>

        <section id="limits">
          <h2>Limits</h2>
          <ul>
            <li>These are climate averages, not forecasts. A given week can be
              much warmer, colder or wetter.</li>
            <li>The grid is about 50 km. Mountains, valleys and coasts can
              differ from it by several degrees.</li>
            <li>Rainy days above 1 mm are an estimate (see above), not a count.</li>
            <li>Altitude matters: a pass at 2,000 m is far colder than the grid
              cell's average.</li>
          </ul>
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
