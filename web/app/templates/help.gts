import Component from '@glimmer/component';
import { service } from '@ember/service';
import { LinkTo } from '@ember/routing';
import { pageTitle } from 'ember-page-title';
import { TabNav } from 'frontile/navigation';
import { Switch } from 'frontile/forms';
import type RouterService from '@ember/routing/router-service';
import SECTIONS from 'forkcast/help-sections.json';
import type AtlasService from 'forkcast/services/atlas';
import type HelpController from 'forkcast/controllers/help';
import Logo from 'forkcast/components/logo';
import Legend from 'forkcast/components/legend';
import { RAIN_THRESHOLDS } from 'forkcast/utils/climate';
import { rainEmojiTiers } from 'forkcast/utils/layers';
import TempScale from 'forkcast/components/help/temp-scale';
import DaylightDemo from 'forkcast/components/help/daylight-demo';
import AltitudeDemo from 'forkcast/components/help/altitude-demo';
import StartDemo from 'forkcast/components/help/start-demo';
import Measured from 'forkcast/components/help/measured';
import {
  BacktestTable,
  EnsoTable,
  ShiftTable,
  VersusTable,
  backtestFrom,
  backtestTo,
  backtestYears,
} from 'forkcast/components/help/climate-measurements';

/** The tabs written for Nerd mode so far; the others show their normal version. */
const NERD_TABS = ['climates'];

export default class Help extends Component<{
  Args: { controller: HelpController };
}> {
  @service declare atlas: AtlasService;
  @service declare router: RouterService;

  /** The section shown: the route's, or the first on /help (and for an unknown one). */
  get section(): string {
    const raw = this.router.currentRoute?.params?.['section'] as
      string | undefined;
    const known = SECTIONS.find((s) => s.id === raw);
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

  /**
   * Nerd mode: every tab's full detail (how each number is made, and how well
   * it holds up) instead of the plain version for riders.
   */
  get isNerd() {
    return this.args.controller.nerd;
  }

  /** Nerd mode is on but this tab has only its normal version yet. */
  get isNerdMissing() {
    return this.isNerd && !NERD_TABS.includes(this.section);
  }

  setNerd = (on: boolean) => {
    this.args.controller.nerd = on;
  };

  /** The rain emoji's steps for each rainy-day threshold, as the map uses them. */
  rainSteps = RAIN_THRESHOLDS.map((mm) => ({
    mm,
    kind: { 1: 'any rain', 5: 'a real shower; the default', 10: 'a soaking' }[
      mm
    ],
    tiers: rainEmojiTiers(mm),
  }));

  get years() {
    const y = this.atlas.climate?.years;
    return y ? `${y[0]}–${y[1]}` : '2011–2025';
  }

  get routeCount() {
    return this.atlas.presets.filter((r) => r.group === 'EuroVelo').length;
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
        <div class="wt-help-nerd">
          <Switch
            @label="Nerd mode"
            @size="sm"
            @isSelected={{this.isNerd}}
            @onChange={{this.setNerd}}
          />
          <span class="wt-help-nerd-hint">{{if
              this.isNerd
              "How each number is made, and how well it holds up."
              "Switch on for the formulas and the measurements."
            }}</span>
        </div>
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
        {{#if this.isNerdMissing}}
          <p class="wt-help-nerd-missing">This tab has no nerd version yet, so
            here's the normal one.</p>
        {{/if}}
        {{#if (this.shows "map")}}
          <section id="map">
            <h2>The map</h2>
            <p>
              The map shows what a typical week is like: the average of the same
              week over
              {{this.years}}, not a forecast. Use it to see which part of the
              year suits a region, and how the weather changes along the way.
              “Climate” switches to the last 10 or 5 years, or to a year with El
              Niño or La Niña; see
              <LinkTo @route="help.section" @model="climates">Climates</LinkTo>.
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
              <strong>high</strong>, or the
              <strong>low</strong>
              if you switch to it. The same colours fill the temperature pills
              for a day of your trip and for a spot on the map:
            </p>
            <TempScale />

            <h3>Rain</h3>
            <p>
              The emoji show how many
              <strong>rainy days</strong>
              a typical week brings. Where it's fewer than one there's nothing,
              so the clear parts of the map are the dry ones.
            </p>
            <p>
              What counts as a rainy day is your choice under “Rainy day”: at
              least 1, 5 or 10 mm of rain. Heavier rain is rarer, so the steps
              follow your choice (the legend always shows the current ones), in
              rainy days a week:
            </p>
            <dl class="wt-help-defs">
              {{#each this.rainSteps as |r|}}
                <div><dt>{{r.mm}} mm</dt><dd>
                    {{#each r.tiers as |t|}}
                      <span class="wt-help-rain-step">{{t.emoji}}
                        {{t.label}}</span>
                    {{/each}}
                    <span class="wt-help-rain-kind">({{r.kind}})</span>
                  </dd></div>
              {{/each}}
            </dl>
            <p>
              Switch to
              <strong>mm</strong>
              to see the amount instead, as dots that grow with the week's rain.
              When you zoom out, neighbouring emoji or dots merge into one
              showing their average.
            </p>

            <h3>The legend</h3>
            <p>
              The legend in the corner of the map gives the colour scale and
              what the rain emoji (or the dot sizes) mean for the week. Click it
              to fold it into a chip, and again to bring it back; this one works
              too:
            </p>
            <div class="wt-help-demo">
              <Legend />
            </div>

            <h3>Dates on the route</h3>
            <p>
              Small tags over your route's night stops show where you'll be as
              time passes. With
              <strong>Months</strong>, a tag such as “Nov” marks where you sleep
              on the 1st of that month; with
              <strong>Weeks</strong>, “Week 2” marks where you sleep on the
              first day of that week of the trip. If that day is a rest day, the
              tag sits where you're resting. Switch them off under “Dates on the
              route”.
            </p>

            <h3>Cities</h3>
            <p>
              “Cities” picks which town names the map shows:
              <strong>10 biggest</strong>, the 10 biggest towns in each country;
              <strong>500k+</strong>, every town of over 500,000 people; or
              none. Capitals are in bold. Capitals always show; until you zoom
              in on a region, only they keep their names.
            </p>

            <h3>More on the map</h3>
            <p>The buttons at the bottom of “Map” switch details on and off:</p>
            <dl class="wt-help-defs">
              <div><dt>Borders</dt><dd>Country outlines.</dd></div>
              <div><dt>Relief</dt><dd>Hill shading, so mountain ranges stand
                  out. It only darkens, so the temperature colours stay true.</dd></div>
              <div><dt>Water</dt><dd>Main rivers and lakes; many routes follow a
                  river.</dd></div>
              <div><dt>Routes</dt><dd>The dashed routes you haven't picked. Your
                  own routes show here too. Click one to pick it; the picked
                  route always shows.</dd></div>
            </dl>
            <p>
              City names and water are downloaded only once you switch them on.
            </p>

            <h3>The whole world</h3>
            <p>
              Forkcast opens on Europe, but the climate covers every continent
              but Antarctica, in 10° squares of a few dozen kB each. The squares
              your route crosses load by themselves. Every other square is
              outlined on the map: click one to load its climate. Forkcast
              remembers the squares you loaded for your next visit.
            </p>

            <h3>Pointing at the map</h3>
            <p>
              Point at the map (tap, on a phone) to read that spot's averages
              for the week: the low and high, the week's rain and how many of
              its days are rainy. Point at your route instead to see which day
              of your trip you'd be there, and the weather expected on that
              date.
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

            <h3>Picking a start date</h3>
            <p>
              The start date's calendar is coloured by the weather where your
              route begins if you set off that day: the high, or the low when
              the map shows lows, in the map's colours. A good time to leave
              stands out at a glance; hover over a day to read its temperature.
              Try a few starting towns:
            </p>
            <StartDemo />

            <h3>The day chart</h3>
            <p>
              Under the map, one column per day, numbered along the top:
            </p>
            <ul>
              <li>a
                <strong>bar</strong>
                from the low to the high, coloured by the high;</li>
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
              <div><dt>Low</dt><dd>The low where you sleep, at the end of the
                  day's ride.</dd></div>
              <div><dt>High</dt><dd>The day's high in the middle of the day's
                  ride, where you spend most of the riding hours.</dd></div>
              <div><dt>(9 to 20 °C)</dt><dd>In brackets next to the low and the
                  high: the usual range, where 8 days in 10 fall at that time of
                  year. The thin line through each day's bar in the chart shows
                  it, from the usual highest high to the usual lowest low. How
                  wide it is depends on the place: a few degrees by the sea or
                  in the tropics, 15 °C and more in a continental winter.</dd></div>
              <div><dt>Rain</dt><dd>The chance that the day is rainy, and how
                  much rain a day brings when it rains (at least 1 mm), also in
                  the middle of the ride. That says more than an average spread
                  over the dry days too: 1 mm a day on average can be a drizzle
                  every day or a downpour once a fortnight.</dd></div>
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
                  up: how many to expect, not a promise. In brackets, the range
                  8 trips out of 10 fall in. Rain comes in spells, so some trips
                  catch a lot more and some a lot less.</dd></div>
              <div><dt>Highest high, likely</dt><dd>The highest single high your
                  trip is as likely to beat as not, in a usual year. Heat comes
                  in spells, which Forkcast takes into account.</dd></div>
              <div><dt>Lowest low, likely</dt><dd>The same for the lowest single
                  low: half of trips get a lower one. Pack for a few degrees
                  below it.</dd></div>
              <div><dt>Lowest average low</dt><dd>The lowest average low of the
                  trip, and its date: when to expect the cold, where the likely
                  lowest low is how cold.</dd></div>
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
              Forkcast combines three well-established climate datasets, each
              for what it does best, all from
              {{this.years}}.
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
              <div><dt>NOAA CPC</dt><dd>Daily highs and lows from the world's
                  weather stations, from the US National Oceanic and Atmospheric
                  Administration. Forkcast uses it to measure how far single
                  days stray from the average, place by place: the usual ranges
                  and the likely lowest low and highest high.</dd></div>
            </dl>
            <p>
              Both are prepared in advance on a grid of 0.25° (about 25 km),
              split into 10° squares that load as you need them.
            </p>

            <h3>How they're turned into the numbers</h3>
            <dl class="wt-help-defs">
              <div><dt>Rain</dt><dd>From ERA5-Land's daily rain totals. Every
                  day from
                  {{this.years}}
                  is checked against 1, 5 and 10 mm, so rainy days are counted,
                  not estimated. A day's chance of being rainy is the share of
                  such days at that time of year.</dd></div>
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
              shows the correction when it's 0.5 °C or more; the map colours
              themselves are the cell averages. Try it:
            </p>
            <AltitudeDemo />
          </section>
        {{/if}}

        {{#if (this.shows "climates")}}
          {{#if this.isNerd}}
            <section id="climates">
              <h2>Climates</h2>
              <p>
                Each climate is a grid of monthly values (highs, lows, rain,
                rainy days at 1, 5 and 10 mm) on 0.25° cells, turned into
                seasonal curves for the app (see Data). 15 yrs is the base;
                every other climate is 15 yrs plus a correction, so where
                nothing changes it is the same, byte for byte.
              </p>

              <h3>15 yrs</h3>
              <p>
                The average of each month over
                {{this.years}}
                from ERA5-Land, highs and lows calibrated against CRU TS station
                data (see Data).
              </p>

              <h3>10 yrs, 5 yrs, 1 yr</h3>
              <p>
                The correction is the window's average minus the average of
                {{this.years}}, both measured on the same ERA5-Land months:
              </p>
              <ul>
                <li><strong>Highs and lows:</strong>
                  the difference in °C is added.</li>
                <li><strong>Rain:</strong>
                  multiplied by the ratio of the two averages, between 0.5 and 2
                  (for 1 yr, between 0 and 10, as a real month can be dry or
                  soaked); months with under 1 mm keep their rain.</li>
                <li><strong>Rainy days:</strong>
                  the difference in days is added, kept within the month, and
                  days over 10 mm never outnumber days over 5 mm, nor those days
                  over 1 mm.</li>
              </ul>

              <h3>El Niño and La Niña</h3>
              <ol>
                <li><strong>Which months:</strong>
                  from NOAA's Oceanic Niño Index, a month is El Niño (La Niña)
                  when it lies in a run of at least 5 overlapping three-month
                  seasons at +0.5 °C or more (−0.5 °C or less), over 1981–2025.</li>
                <li><strong>Departures:</strong>
                  for each cell and month of the year, each year's value minus
                  that cell's straight-line trend over 1981–2025, so recent
                  warming isn't mistaken for El Niño just because recent years
                  had more of them.</li>
                <li><strong>The correction:</strong>
                  the average departure over the event's months, kept only where
                  it beats chance: the same average over 100 random sets of as
                  many years is worked out, and the correction is kept in full
                  where it's larger than 90% of them, fading to nothing at 75%.
                  A month seen in fewer than 2 events gets none. Then it's
                  smoothed over 3 × 3 cells and applied as above.</li>
                <li><strong>Checks:</strong>
                  the build stops if a well-known effect comes out the wrong way
                  round, if an area's average high moves implausibly, or if any
                  cell's highs or lows move by more than 6 °C (15 °C for 1 yr;
                  the Tibetan Plateau, with a known flaw in the data, has its
                  own limit).</li>
              </ol>

              <Measured as |m|>
                <EnsoTable @measurements={{m}} />

                <h3>How far each climate moves the highs</h3>
                <ShiftTable @measurements={{m}} />

                <h3>Which climate plans best</h3>
                <p>
                  Our guess against what then happened: for each year from
                  {{backtestFrom m}}
                  to
                  {{backtestTo m}}
                  ({{backtestYears m}}
                  years), each climate is made of the years before it (the last
                  15, 10 or 5, or just the last one) and compared with that
                  year's real months, in every land cell.
                </p>
                <ul>
                  <li><strong>Why these years:</strong>
                    the data starts in 1981 and 15 yrs needs 15 years before the
                    year it's tested on, so 1996 is the first; 2025 the last
                    there is.</li>
                  <li><strong>The sample is the years.</strong>
                    Neighbouring cells and months share their weather, so
                    counting millions of cell-months would make the results look
                    far more certain than they are. One year's weather says
                    little about the next, so the years are close to
                    independent.</li>
                  <li><strong>How precise:</strong>
                    each error comes with a 95% interval, from resampling the
                    years 2,000 times (bootstrap): the narrower, the more
                    certain.</li>
                  <li><strong>Telling two climates apart:</strong>
                    the climates are compared year by year (the same weather
                    tests both), which is far more precise than comparing their
                    two intervals. Only where the interval of the difference
                    leaves out 0 is one better or worse.</li>
                  <li><strong>Raw ERA5-Land:</strong>
                    the test uses the uncalibrated monthly values, the same for
                    every climate, so it compares the choice of years, not the
                    calibration.</li>
                </ul>
                <BacktestTable @measurements={{m}} @area="Europe" />
                <VersusTable @measurements={{m}} @area="Europe" />
                <BacktestTable @measurements={{m}} @area="World" />
                <VersusTable @measurements={{m}} @area="World" />
              </Measured>
            </section>
          {{else}}
            <section id="climates">
              <h2>Climates</h2>
              <p>
                Forkcast doesn't forecast the weather. It shows what the weather
                is usually like: the average of past years. “Climate”, in the
                Map settings, picks which years.
              </p>

              <h3>15 yrs</h3>
              <p>
                Made from
                {{this.years}}. Enough years that one unusually hot, cold or wet
                year doesn't throw things off, and recent enough to show today's
                warmer climate. Of the choices, it's the one that would have
                predicted past years best, so it's what Forkcast starts with.
              </p>

              <h3>10 yrs, 5 yrs</h3>
              <p>
                Made from only the most recent years. They come out a little
                warmer, by about 0.2–0.5 °C, because the climate keeps warming.
                But the fewer the years, the more a single odd year shows,
                especially in the rain. Good for seeing how things are changing;
                for planning, 15 yrs is the safer choice.
              </p>

              <h3>1 yr</h3>
              <p>
                Only the most recent year, 2025, each month as it really was:
                Spain's record-hot June is there, and so is every wet or dry
                month of the year. Ride your trip through it to see how a real
                year can differ from the average, for better or worse. One year
                is just one roll of the dice, so don't plan by it alone. Each
                place still shows its monthly averages for 2025, so a single hot
                week or storm within a month is smoothed out.
              </p>

              <h3>El Niño and La Niña</h3>
              <p>
                Every few years the tropical Pacific runs warmer than usual (El
                Niño) or cooler (La Niña), and that shifts the weather in many
                parts of the world. Weather services announce them months ahead
                (look for an “ENSO outlook”). If one is expected during your
                trip, pick it to see what it usually changes.
              </p>
              <ul>
                <li><strong>Where it matters:</strong>
                  Australia, northern South America, southern Africa and parts
                  of North America. El Niño, for example, brings a drier spring
                  to eastern Australia and a milder winter to western Canada; La
                  Niña mostly the opposite.</li>
                <li><strong>Europe:</strong>
                  hardly at all. The map barely changes there.</li>
                <li><strong>How it's done:</strong>
                  we looked at how the weather differed during the El Niños and
                  La Niñas since 1981, and added that difference to 15 yrs.
                  Where the difference could just be chance, nothing changes.</li>
                <li><strong>A tendency, not a promise:</strong>
                  one El Niño year can still turn out quite unlike another.</li>
              </ul>
            </section>
          {{/if}}
        {{/if}}

        {{#if (this.shows "accuracy")}}
          <section id="accuracy">
            <h2>How far to trust it</h2>
            <p>
              The biggest uncertainty isn't in the maths but in the weather
              itself. From the station records for
              {{this.years}}:
            </p>
            <ul>
              <li><strong>Year to year,</strong>
                a month's average high in Europe typically varies by ±1.3 to
                ±1.7 °C; more in continental winters (Kraków in January ±2.1 °C)
                and less by the Mediterranean (Valencia in January ±0.9 °C).</li>
              <li><strong>Day to day</strong>
                the spread is far larger, which is why each day comes with its
                usual range: 8 days in 10 fall in it, so 1 in 10 is warmer and 1
                in 10 colder. Read the numbers as “what to pack for”, not “what
                it will be”.</li>
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
                in the Alps still come out 2–3 °C too mild, lows more: cold air
                pooling and fog are too local for the data. Expect colder winter
                mornings in valleys.</li>
              <li><strong>Tibetan Plateau winters</strong>
                jump about 10 °C warmer in the data from 2021 on, most likely a
                flaw in how it tracks snow there. Winters on the Plateau come
                out too mild, most of all in the 5-year climate.</li>
              <li><strong>Few stations</strong>
                in deserts, high mountains and parts of Africa, Asia and South
                America make the highs and lows less certain there.</li>
              <li><strong>Smooth seasons.</strong>
                The curve through the year can't change faster than about four
                months, so a rainy season that starts within two weeks is shown
                starting more gently, over a month or so.</li>
              <li><strong>Warming.</strong>
                The data is from
                {{this.years}}, centred on 2018; in Europe temperatures rise by
                about 0.5 °C per decade, so this year is likely a few tenths
                warmer than shown. The 5-year climate is closer.</li>
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
              Your plan lives in the page address: climate, week, map layers,
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
            <p>
              One thing does show: the climate data comes in 10° squares, and
              your browser fetches the ones your route crosses and the ones you
              click. The site's host could see which squares of the world were
              looked at, though not your route, dates or anything else in your
              plan.
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
                ECMWF is responsible for any use of it. How far single days
                stray:
                <a
                  href="https://psl.noaa.gov/data/gridded/data.cpc.globaltemp.html"
                  target="_blank"
                  rel="noopener noreferrer"
                >CPC Global Unified Temperature</a>
                data provided by the NOAA PSL, Boulder, Colorado, USA, from
                their website at https://psl.noaa.gov.
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
                <strong>Borders, cities, rivers and lakes:</strong>
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

        {{#if (this.shows "about")}}
          <section id="about">
            <h2>About Forkcast</h2>
            <p>
              Forkcast is made by
              <a
                href="https://vast.ch/earth/"
                target="_blank"
                rel="noopener noreferrer"
              >vast.earth</a>. It's free, has no accounts, and nothing about you
              or your trip leaves your browser (see
              <LinkTo @route="help.section" @model="sharing">Sharing &amp;
                privacy</LinkTo>).
            </p>

            <h3>Found a bug? Missing something?</h3>
            <p>
              Forkcast is open source on GitHub. Tell us what went wrong, or
              what would make your planning easier:
              <a
                href="https://github.com/vast-ch/forkcast/issues/new"
                target="_blank"
                rel="noopener noreferrer"
              >report an issue or request a feature</a>. What has changed lately
              is under
              <LinkTo @route="changelog">What's new</LinkTo>.
            </p>

            <h3>Chat with us</h3>
            <p>
              Questions, trip stories, ideas: join the Forkcast channel on
              Discord. Scan the code with your phone, or
              <a
                href="https://discord.gg/ZjhUHZCeNr"
                target="_blank"
                rel="noopener noreferrer"
              >open it here</a>.
            </p>
            <img
              class="wt-help-qr"
              src="/discord-qr.svg"
              alt="QR code for the Forkcast channel on Discord"
              width="160"
              height="160"
            />
          </section>
        {{/if}}
      </article>
    </div>
  </template>
}
