import Component from '@glimmer/component';
import { service } from '@ember/service';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';
import type AtlasService from 'forkcast/services/atlas';
import Logo from 'forkcast/components/logo';

export default class Help extends Component {
  @service declare atlas: AtlasService;

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
        <LinkTo @route="index" class="wt-help-link">← Back to the map</LinkTo>
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
            <strong>night low</strong>) for the chosen week. Dots show rain on
            top of it: the dot's area grows with the week's rainfall, or with
            the number of rainy days if you switch to that. When you zoom out,
            neighbouring dots merge into one showing their average, so they stay
            readable. Forkcast opens on Europe and the current week (drag the
            slider under “Map”: it moves a quarter of a month, about a week, at
            a time); the other continents are drawn as light shapes, and
            clicking one adds its climate (a one-off download of 1–5 MB). You
            can show several at once, for a trip that crosses from one into
            another. Point at the map to read the averages for that spot in the
            week shown (its rain in total, and how many of its days are rainy);
            point at your route to see the day you would be there and the
            weather expected on that date.
          </p>
        </section>

        <section id="data">
          <h2>Where the weather data comes from</h2>
          <p>
            Forkcast combines two well-established climate datasets, each used
            for what it does best.
          </p>
          <dl class="wt-help-defs">
            <div><dt>ERA5-Land</dt><dd>From the European Copernicus Climate
                Change Service. A weather model re-run over past years and
                continuously corrected with real observations, giving the
                weather for every hour over all land at a fine resolution.
                Forkcast uses it for rain and for the shape of the temperatures:
                where it is warmer or cooler, coast against hills, valley
                against plateau.</dd></div>
            <div><dt>CRU TS</dt><dd>From the University of East Anglia. Built
                from thousands of weather stations, coarser (about 50 km), but
                its daily highs and lows are averages of what thermometers
                actually recorded. Forkcast uses it to set the level of the
                highs and lows (see below).</dd></div>
          </dl>
          <p>
            Both cover the
            {{this.years}}
            period, 15 years: long enough that one odd year doesn't dominate,
            recent enough to include most of the warming so far. Every January
            on the map is the average of 15 Januaries: what a typical year looks
            like, not a forecast.
          </p>
          <p>
            The data is prepared in advance on a grid of 0.25° (about 25 km) and
            split by continent, so opening a continent downloads a few megabytes
            once; your browser then keeps it.
          </p>
        </section>

        <section id="maths">
          <h2>How it is calculated</h2>
          <dl class="wt-help-defs">
            <div><dt>Rain</dt><dd>From ERA5-Land's daily rain totals. For every
                day of the 15 years we check whether it reached 1, 5 or 10 mm
                and count those days per month, then average over the years. So
                rainy days are counted, not guessed. The chance that a given day
                is rainy is the month's rainy days divided by its length.</dd></div>
            <div><dt>Day high and night low</dt><dd>ERA5-Land gives the average
                temperature for each hour of a typical day of the month. Its
                warmest hour is a little cooler than the average daily high,
                because on real days the peak comes at different times (and the
                same, the other way round, for the coldest hour). So the highs
                and lows are shifted to match the station-measured daily
                extremes from CRU, averaged over each 50 km area, while keeping
                ERA5-Land's finer detail inside it. Over Europe's land the shift
                is 1.4–1.8 °C for highs and 1.1–2.0 °C for lows, depending on
                the month.</dd></div>
            <div><dt>Altitude</dt><dd>A 25 km grid cell has one average height,
                but a valley town or a pass on your route can be hundreds of
                metres above or below it. Air cools with height, so on your
                route the high and low are corrected for the difference between
                the route's height and the cell's: by about 6.8 °C per 1,000 m
                in summer and 4.5 °C in winter, when cold air settles in valleys
                (the seasonal rates measured across the Alps). Pointing at the
                route shows the correction when it is half a degree or more. The
                map colours themselves show the cell averages.</dd></div>
            <div><dt>Between grid points</dt><dd>A place's value is a weighted
                average of the four surrounding grid points, closer ones
                counting more. Over the sea there is no data; near the coast
                only the land points are used.</dd></div>
            <div><dt>Through the year</dt><dd>The data comes as twelve monthly
                averages. Forkcast draws a smooth curve through them for every
                place: the yearly average plus three gentle waves (12, 6 and 4
                months long). Every day then gets its own value, so the weather
                changes gradually instead of jumping from one month to the next,
                and the map can show any quarter of a month (roughly a week).
                Rain is smoothed as a daily rate and rainy days as the share of
                days, so short and long months compare fairly.</dd></div>
            <div><dt>Your trip's days</dt><dd>A riding day's high and rain are
                taken in the middle of that day's stretch, where you spend most
                of the riding hours. The night low is taken at the end of the
                stretch, where you sleep. "Rainy riding days" adds up the daily
                chances: the number you should expect, not a promise. "Average
                high" is the average over riding days only.</dd></div>
          </dl>
        </section>

        <section id="precision">
          <h2>How precise it is</h2>
          <p>
            The biggest uncertainty is not in the maths but in the weather
            itself. From the station records for the same 15 years:
          </p>
          <ul>
            <li><strong>Year to year,</strong>
              a month's average high in Europe typically varies by ±1.3 to ±1.7
              °C (one standard deviation); more in continental winters (Kraków
              in January ±2.1 °C, between −2.7 and 3.8 °C) and less on the
              Mediterranean (Valencia in January ±0.9 °C).</li>
            <li><strong>Day to day</strong>
              the spread is far larger: as a rule of thumb single days often sit
              4–6 °C above or below the average. Read the numbers as "what to
              pack for", not "what it will be".</li>
            <li><strong>Rain varies most:</strong>
              a month's rainfall typically differs from its average by about a
              third (Interlaken in January: 92 mm on average, ±44 mm), and
              rainy-day counts move with it.</li>
          </ul>
          <p><strong>Limits of the data and the method:</strong></p>
          <ul>
            <li><strong>Resolution.</strong>
              A 25 km cell averages everything inside it. A narrow coast, a
              lakeshore or a valley can differ from it; the altitude correction
              fixes most of that on your route, but not, say, a seafront town
              whose cell includes hills at the same height.</li>
            <li><strong>Altitude correction</strong>
              uses seasonal averages. Checked against towns' published climate
              it is within about 1 °C in summer, but in winter Alpine valleys
              still come out 2–3 °C too mild, and their nights more: cold air
              pooling in valleys (and fog) is local and not in the data. Expect
              colder winter mornings in valleys than shown.</li>
            <li><strong>Calibration</strong>
              sets the level of highs and lows from weather stations. Where
              stations are sparse (deserts, high mountains, parts of Africa,
              Asia and South America) it is less certain.</li>
            <li><strong>Smoothing is a trade-off.</strong>
              The curve cannot change faster than its shortest wave, about four
              months. Sharp seasonal edges get softened: a rainy season that
              starts within two weeks is shown starting more gently, spread over
              a month or so, and a short dry or cold spell typical of one part
              of a month is blurred into its neighbours. For temperatures this
              costs little (the seasons change smoothly); for rain in monsoon or
              Mediterranean climates the exact start and end of the wet season
              can be off by a couple of weeks.</li>
            <li><strong>Days in UTC.</strong>
              Rain is counted in days from midnight to midnight UTC, which
              shifts the day by an hour or two in Europe. It hardly changes
              monthly counts.</li>
            <li><strong>Warming.</strong>
              The 15-year average is centred on 2018. Temperatures are rising,
              in Europe by roughly 0.5 °C per decade, so this year's normal is
              likely a few tenths warmer than shown.</li>
            <li><strong>Distances and climbing</strong>
              are measured along the route's points. Tracks are simplified a
              little, so climbing comes out somewhat low; drawn routes are
              straight lines and have no height, so no altitude correction.</li>
          </ul>
          <p>
            The values are stored to 0.5 °C and finer for rain, well below the
            real uncertainty, so the app rounds what it shows: whole degrees,
            whole percent.
          </p>
        </section>

        <section id="trip">
          <h2>Trip and days</h2>
          <p>
            The trip starts on your start date and covers the route at your km
            per day. Ride days and rest days form a repeating pattern: ride 5,
            rest 2 means five riding days, two rest days, then again. A trip
            never ends on a rest day. Your average speed (21km/h unless you
            change it) turns each day's distance into time in the saddle, not
            counting breaks, so you can compare it with the daylight. A day
            whose riding time is longer than its daylight gets a 🔦 in the
            chart: you'll ride part of it in the dark, so bring lights or plan a
            shorter day.
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
            <li><strong>Daylight</strong>
              runs from sunrise where the day starts to sunset where it ends,
              worked out from the sun's position (within a minute or two of
              published tables). Riding west makes a day a few minutes longer.
              In the far north it can be the midnight sun or the polar night. It
              is sunrise to sunset; it's usually light enough to ride about half
              an hour before and after.</li>
          </ul>
          <p>
            In the chart, each bar runs from the night low to the day high and
            is coloured by the high, with the day's number above it. The blue
            bar underneath is the chance of a rainy day. Shaded columns are rest
            days, with the weather where you stay. When the map shows a week
            your trip doesn't reach, the Before or After column at the end of
            the chart is highlighted instead of a day. Click a day, or focus the
            chart and use the arrow keys, to see its numbers and its stretch on
            the map.
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
                href="https://cds.climate.copernicus.eu/datasets/reanalysis-era5-land"
                target="_blank"
                rel="noopener noreferrer"
              >ERA5-Land</a>, Copernicus Climate Change Service (C3S) Climate
              Data Store, ECMWF: daily rain, hourly temperature and terrain
              height. Calibrated with
              <a
                href="https://crudata.uea.ac.uk/cru/data/hrg/"
                target="_blank"
                rel="noopener noreferrer"
              >CRU TS 4.10</a>, Climatic Research Unit, University of East
              Anglia. Both averaged over
              {{this.years}}. Contains modified Copernicus Climate Change
              Service information 2026; neither the European Commission nor
              ECMWF is responsible for any use of it.
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
