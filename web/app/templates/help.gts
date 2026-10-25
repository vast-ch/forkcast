import Component from '@glimmer/component';
import { service } from '@ember/service';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';
import { TabNav } from 'frontile/navigation';
import type RouterService from '@ember/routing/router-service';
import SECTIONS from 'forkcast/help-sections.json';
import type AtlasService from 'forkcast/services/atlas';
import Logo from 'forkcast/components/logo';
import Legend from 'forkcast/components/legend';
import TempScale from 'forkcast/components/help/temp-scale';
import DaylightDemo from 'forkcast/components/help/daylight-demo';
import AltitudeDemo from 'forkcast/components/help/altitude-demo';

/** Sections that were renamed or merged: old links still land on the right tab. */
const ALIASES: Record<string, string> = {
  maths: 'data',
  precision: 'accuracy',
  links: 'sharing',
  privacy: 'sharing',
};

export default class Help extends Component {
  @service declare atlas: AtlasService;
  @service declare router: RouterService;

  /** The section shown: the route's, or the first on /help (and for an unknown one). */
  get section(): string {
    const raw = this.router.currentRoute?.params?.['section'] as
      string | undefined;
    const id = raw && (ALIASES[raw] ?? raw);
    const known = SECTIONS.find((s) => s.id === id);
    return (known ?? SECTIONS[0]!).id;
  }

  get sections() {
    return SECTIONS.map((s, i) => ({
      ...s,
      isFirst: i === 0,
      isActive: s.id === this.section,
    }));
  }

  get sectionLabel() {
    return SECTIONS.find((s) => s.id === this.section)!.label;
  }

  shows = (id: string) => this.section === id;

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
    {{pageTitle this.sectionLabel " · How it works"}}
    <div class="wt-help-page">
      <header class="wt-help-header">
        <nav class="flex justify-between">
          <LinkTo @route="index" class="wt-help-link">← Back to the map</LinkTo>
          <LinkTo @route="changelog" class="wt-help-link">What's new</LinkTo>
        </nav>
        <h1 class="wt-logo-heading mt-3"><LinkTo
            @route="index"
            aria-label="Forkcast home"
          ><Logo /></LinkTo></h1>
        <p class="wt-help-lede">What the weather usually does along your bike
          route, day by day: how to read it, where the numbers come from, and
          how far to trust them.</p>
      </header>

      <TabNav
        @label="Help sections"
        @variant="underline"
        @size="sm"
        class="wt-help-tabs"
        as |Nav|
      >
        {{#each this.sections as |sec|}}
          <Nav.Item
            @route={{if sec.isFirst "help.index" "help.section"}}
            @model={{unless sec.isFirst sec.id}}
            @isActive={{sec.isActive}}
          >{{sec.label}}</Nav.Item>
        {{/each}}
      </TabNav>

      <article class="wt-help">
        {{#if (this.shows "map")}}
          <section id="map">
            <h2>The map</h2>
            <p>
              The map shows what a typical week is like: the average of the same
              week over
              {{this.years}}, not a forecast. Use it to see which part of the
              year suits a region, and how the weather changes along the way.
            </p>

            <h3>Time of year</h3>
            <p>
              The slider under “Map” picks the week, a quarter of a month at a
              time; the arrow keys step it. Moving it also moves the day chart
              to your trip's first day in that week (see Trip), and picking a
              day moves the map to its week.
            </p>

            <h3>Temperature</h3>
            <p>
              The colour is the average
              <strong>day high</strong>, or the
              <strong>night low</strong>
              if you switch to it. The same colours fill the temperature pills
              for a day of your trip and for a spot on the map:
            </p>
            <TempScale />

            <h3>Rain</h3>
            <p>
              Each dot's area grows with the week's rain, in millimetres, or
              with the number of rainy days if you switch to that. A rainy day
              is one with at least 1, 5 or 10 mm of rain, your choice under
              “Rainy day”. When you zoom out, neighbouring dots merge into one
              showing their average, so they stay readable.
            </p>

            <h3>The legend</h3>
            <p>
              The legend in the corner of the map gives the colour scale and the
              dot sizes for the week. Click it to fold it into a chip, and again
              to bring it back; this one works too:
            </p>
            <div class="wt-help-demo">
              <Legend />
            </div>

            <h3>More on the map</h3>
            <p>The buttons at the bottom of “Map” switch details on and off:</p>
            <dl class="wt-help-defs">
              <div><dt>Borders</dt><dd>Country outlines.</dd></div>
              <div><dt>Cities</dt><dd>Towns of 50,000 or more (capitals in bold)
                  and the names of mountain ranges. They show at every zoom, so
                  switch them off for a calmer map.</dd></div>
              <div><dt>Relief</dt><dd>Hill shading, so mountain ranges stand
                  out. It only darkens, so the temperature colours stay true.</dd></div>
              <div><dt>Water</dt><dd>Main rivers and lakes; many routes follow a
                  river.</dd></div>
              <div><dt>Routes</dt><dd>The dashed routes you haven't picked. Your
                  own routes show here too. Click one to pick it; the picked
                  route always shows.</dd></div>
            </dl>
            <p>
              Cities and water are downloaded only once you switch them on.
            </p>

            <h3>Continents</h3>
            <p>
              Forkcast opens on Europe. Other continents are drawn as light
              shapes: click one to add its climate, a one-off download of 1–5
              MB. You can show several at once, for a trip that crosses from one
              into another.
            </p>

            <h3>Pointing at the map</h3>
            <p>
              Point at the map (tap, on a phone) to read that spot's averages
              for the week: the night low and day high, the week's rain and how
              many of its days are rainy. Point at your route instead to see
              which day of your trip you'd be there, and the weather expected on
              that date.
            </p>
          </section>
        {{/if}}

        {{#if (this.shows "trip")}}
          <section id="trip">
            <h2>Your trip</h2>
            <p>
              Pick a route, then set the trip under “Trip”: the
              <strong>start</strong>
              date, how many
              <strong>km per day</strong>
              you ride, your
              <strong>average speed</strong>, and a pattern of
              <strong>ride days</strong>
              and
              <strong>rest days</strong>. Ride 5, rest 2 means five riding days,
              two rest days, then again. A trip never ends on a rest day.
            </p>

            <h3>The day chart</h3>
            <p>
              Under the map, one column per day, numbered along the top:
            </p>
            <ul>
              <li>a
                <strong>bar</strong>
                from the night low to the day high, coloured by the high;</li>
              <li>underneath, the
                <strong>chance of a rainy day</strong>;</li>
              <li>a
                <strong>🔦</strong>
                under the day number when the day's riding takes longer than its
                daylight;</li>
              <li><strong>shaded columns</strong>
                for rest days, with the weather where you stay;</li>
              <li>a
                <strong>line</strong>
                with the month's name where a new month starts.</li>
            </ul>
            <p>
              Click a column, or focus the chart and use the arrow keys (Home
              and End jump to the ends), to pick a day: it turns purple, here
              and on the map, and its numbers appear above the chart. When the
              map shows a week your trip doesn't reach, the
              <strong>Before</strong>
              or
              <strong>After</strong>
              column at the end of the chart is highlighted instead, depending
              on which end of the trip is nearer.
            </p>

            <h3>A day's numbers</h3>
            <dl class="wt-help-defs">
              <div><dt>Low</dt><dd>The night's low where you sleep, at the end
                  of the day's ride.</dd></div>
              <div><dt>High</dt><dd>The day's high in the middle of the day's
                  ride, where you spend most of the riding hours.</dd></div>
              <div><dt>Rain</dt><dd>The chance that the day is rainy, and the
                  average rain, also in the middle of the ride.</dd></div>
              <div><dt>Distance</dt><dd>With the stretch of the route (km from
                  the start) and the climbing: every ascent along it added up.</dd></div>
              <div><dt>Riding</dt><dd>The distance at your average speed: time
                  in the saddle, without breaks.</dd></div>
              <div><dt>Daylight</dt><dd>From sunrise where the day starts to
                  sunset where it ends.</dd></div>
            </dl>

            <h3>Daylight and lights</h3>
            <p>
              Daylight is worked out from the sun's position, within a minute or
              two of published tables. Riding west makes a day a few minutes
              longer, since the sun sets later where you arrive. In the far
              north it can be the midnight sun or the polar night. It is sunrise
              to sunset; it's usually light enough to ride for about half an
              hour either side. When the riding time is longer than the
              daylight, the day gets a 🔦. Try it:
            </p>
            <DaylightDemo />

            <h3>The summary</h3>
            <dl class="wt-help-defs">
              <div><dt>Days</dt><dd>The whole trip, riding and rest days, and
                  the arrival date.</dd></div>
              <div><dt>Average high</dt><dd>Over riding days only.</dd></div>
              <div><dt>Rainy riding days</dt><dd>The day-by-day chances added
                  up: how many to expect, not a promise.</dd></div>
              <div><dt>Coldest night</dt><dd>The trip's lowest night, and its
                  date.</dd></div>
            </dl>

            <h3>On a phone</h3>
            <p>
              The map comes first, then the day chart and the summary. All the
              settings are in the “Settings” drawer at the top.
            </p>
          </section>
        {{/if}}

        {{#if (this.shows "routes")}}
          <section id="routes">
            <h2>Routes</h2>

            <h3>Ready-made routes</h3>
            <p>
              All
              {{this.routeCount}}
              EuroVelo routes are built in, from the official EuroVelo tracks.
              Where a route offers variants, such as both banks of a river or
              alternatives through different countries, Forkcast follows the
              shortest way from start to finish; ferries count as travel time,
              not riding distance. The demo route, Interlaken – Málaga, runs
              down the Rhône valley and Spain's east coast, routed for touring
              bikes on cycle-friendly roads.
            </p>
            <p>
              Pick a route in the list or click a dashed one on the map. The ⇅
              button next to the list rides it the other way.
            </p>

            <h3>Drawing your own</h3>
            <p>
              Press “Draw a route” and click the map. With
              <strong>Follow cycle routes</strong>
              on, each click moves onto the nearest international cycle route
              within 25 km (in Europe, the EuroVelo routes), and your route
              follows the cycle routes from one click to the next by the
              shortest way. Add clicks to steer it. Where there's no route near,
              it goes straight. The routes you can follow show as white lines
              while you draw, and your clicks as a thin dashed line.
            </p>
            <p>
              Switch “Follow cycle routes” off for straight lines between your
              clicks; you can switch it at any time. Undo takes back the last
              click; double-click or press Save to finish. Drawn routes have no
              height, so no climbing and no altitude correction.
            </p>

            <h3>Your routes</h3>
            <p>
              Every route you draw or import is kept, under “Your routes” in the
              list and dashed on the map. Name a route as you draw it (it starts
              as Route 1, Route 2 and so on; an imported one takes the name in
              its file). Pick one and press “Edit route” to change it: a drawn
              route goes back into drawing, with your clicks as you left them,
              to add to, undo and save over the old one, and the day chart and
              trip follow as you draw; an imported track can't be reshaped that
              way, so for it Edit route changes the name only. “Delete this
              route” removes it.
            </p>
            <p>
              They're kept in this browser only, whole and as long as you like
              (any size of GPX works), never on a server. The link to one says
              which of your routes it is, not the route itself, so it opens only
              in the browser where the route was made. To give a route to
              someone, send them its GPX file. Clearing this site's data in your
              browser deletes them; export a GPX of any you want to keep.
            </p>

            <h3>GPX files</h3>
            <p>
              “Import GPX” adds the track in your file to your routes, with its
              heights, so climbing and the altitude correction work. “Export
              GPX” saves the selected route as a file, for your bike computer,
              another app or another browser.
            </p>
          </section>
        {{/if}}

        {{#if (this.shows "data")}}
          <section id="data">
            <h2>Where the numbers come from</h2>
            <p>
              Forkcast combines two well-established climate datasets, each for
              what it does best, both over
              {{this.years}}: 15 years, long enough that one odd year doesn't
              dominate, recent enough to include most of the warming so far.
            </p>
            <dl class="wt-help-defs">
              <div><dt>ERA5-Land</dt><dd>From the European Copernicus Climate
                  Change Service: a weather model re-run over the past and
                  continuously corrected with real observations, giving the
                  weather for every hour over all land. Forkcast uses it for
                  rain, terrain height and the shape of the temperatures: coast
                  against hills, valley against plateau.</dd></div>
              <div><dt>CRU TS</dt><dd>From the University of East Anglia, built
                  from thousands of weather stations. Coarser (about 50 km), but
                  its highs and lows are what thermometers actually recorded, so
                  Forkcast uses it to set their level.</dd></div>
            </dl>
            <p>
              Both are prepared in advance on a grid of 0.25° (about 25 km) and
              split by continent, so opening a continent downloads a few
              megabytes once.
            </p>

            <h3>How they're turned into the numbers</h3>
            <dl class="wt-help-defs">
              <div><dt>Rain</dt><dd>From ERA5-Land's daily rain totals. Every
                  day of the 15 years is checked against 1, 5 and 10 mm, so
                  rainy days are counted, not estimated. A day's chance of being
                  rainy is the share of such days at that time of year.</dd></div>
              <div><dt>Highs and lows</dt><dd>ERA5-Land gives the temperature
                  for each hour of a typical day. Its warmest hour is a little
                  cooler than the average daily high, because real days peak at
                  different times, and the other way round for the coldest. So
                  highs and lows are shifted to the station-measured extremes
                  from CRU, keeping ERA5-Land's finer detail: over Europe by
                  1.4–1.8 °C for highs and 1.1–2.0 °C for lows.</dd></div>
              <div><dt>Through the year</dt><dd>The data comes as twelve monthly
                  averages. Forkcast draws a smooth curve through them for every
                  place, so every day has its own value and the weather changes
                  gradually rather than jumping at each month's end.</dd></div>
              <div><dt>Between grid points</dt><dd>A place's value is a weighted
                  average of the four grid points around it, nearer ones
                  counting more. Near the coast only land points are used.</dd></div>
            </dl>

            <h3>Altitude</h3>
            <p>
              A grid cell has one average height, but a valley or a pass on your
              route can be hundreds of metres above or below it. Air cools with
              height, so on your route the high and low are corrected for the
              difference, using seasonal rates measured across the Alps: smaller
              in winter, when cold air settles in valleys. Pointing at the route
              shows the correction when it's half a degree or more; the map
              colours themselves are the cell averages. Try it:
            </p>
            <AltitudeDemo />
          </section>
        {{/if}}

        {{#if (this.shows "accuracy")}}
          <section id="accuracy">
            <h2>How far to trust it</h2>
            <p>
              The biggest uncertainty isn't in the maths but in the weather
              itself. From the station records for the same 15 years:
            </p>
            <ul>
              <li><strong>Year to year,</strong>
                a month's average high in Europe typically varies by ±1.3 to
                ±1.7 °C; more in continental winters (Kraków in January ±2.1 °C)
                and less by the Mediterranean (Valencia in January ±0.9 °C).</li>
              <li><strong>Day to day</strong>
                the spread is far larger: single days often sit 4–6 °C above or
                below the average. Read the numbers as “what to pack for”, not
                “what it will be”.</li>
              <li><strong>Rain varies most:</strong>
                a month's rainfall typically differs from its average by about a
                third (Interlaken in January: 92 mm on average, ±44 mm).</li>
            </ul>

            <h3>Limits of the data</h3>
            <ul>
              <li><strong>25 km cells</strong>
                average everything inside them. A narrow coast or lakeshore can
                differ; the altitude correction fixes most of that on your
                route, but not, say, a seafront town whose cell includes hills.</li>
              <li><strong>Winter valleys</strong>
                in the Alps still come out 2–3 °C too mild, nights more: cold
                air pooling and fog are too local for the data. Expect colder
                winter mornings in valleys.</li>
              <li><strong>Few stations</strong>
                in deserts, high mountains and parts of Africa, Asia and South
                America make the highs and lows less certain there.</li>
              <li><strong>Smooth seasons.</strong>
                The curve through the year can't change faster than about four
                months, so a rainy season that starts within two weeks is shown
                starting more gently, over a month or so.</li>
              <li><strong>Warming.</strong>
                The 15 years are centred on 2018; in Europe temperatures rise by
                about 0.5 °C per decade, so this year is likely a few tenths
                warmer than shown.</li>
              <li><strong>Climbing</strong>
                comes out somewhat low, because tracks are simplified a little.</li>
            </ul>
            <p>
              The app rounds what it shows, to whole degrees and whole percent,
              since the real uncertainty is far larger.
            </p>
          </section>
        {{/if}}

        {{#if (this.shows "sharing")}}
          <section id="sharing">
            <h2>Sharing and privacy</h2>
            <p>
              Your plan lives in the page address: continents, week, map layers,
              route, start date, distances, speed, rest pattern and the picked
              day. Bookmark it or send the link, and the same plan opens again.
              Settings left at their defaults are left out, so links stay short.
              Your own routes are the exception: they're kept in this browser,
              and a link only names one, so someone else opening it is told to
              ask you for its GPX file.
            </p>
            <p>
              This browser also remembers where you left off: your last plan and
              where the map was. Opening Forkcast without a plan in the address
              picks up from there; opening a link shows the link's plan instead.
            </p>
            <p>
              None of it goes to a server: nothing about you, your plan or your
              routes leaves your browser unless you send the link or a GPX file
              yourself. Forkcast runs entirely in your browser; the site is just
              files, with no server behind it, no account, no cookies, no
              analytics, no ads and no tracking. The page, its fonts and its
              data all come from the site itself, and your browser is told to
              refuse anything from elsewhere. Following a link out of the app
              doesn't pass your plan on.
            </p>
          </section>
        {{/if}}

        {{#if (this.shows "sources")}}
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
                <strong>Cycle routes for drawing:</strong>
                international bicycle routes from ©
                <a
                  href="https://www.openstreetmap.org/copyright"
                  target="_blank"
                  rel="noopener noreferrer"
                >OpenStreetMap</a>
                contributors, fetched with the
                <a
                  href="https://overpass-api.de"
                  target="_blank"
                  rel="noopener noreferrer"
                >Overpass API</a>
                and made available here under the
                <a
                  href="https://opendatacommons.org/licenses/odbl/1-0/"
                  target="_blank"
                  rel="noopener noreferrer"
                >Open Database License (ODbL)</a>.
              </li>
              <li>
                <strong>Borders, cities, mountain ranges, rivers and lakes:</strong>
                <a
                  href="https://www.naturalearthdata.com"
                  target="_blank"
                  rel="noopener noreferrer"
                >Natural Earth</a>, public domain. The relief shading is drawn
                from the ERA5-Land terrain height above.
              </li>
            </ul>
          </section>
        {{/if}}
      </article>
    </div>
  </template>
}
