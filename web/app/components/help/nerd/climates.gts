import type { TOC } from '@ember/component/template-only';
import Measured from 'forkcast/components/help/measured';
import {
  BacktestTable,
  EnsoTable,
  ShiftTable,
  VersusTable,
  WarmingTable,
  backtestFrom,
  backtestTo,
  backtestYears,
} from './climate-tables';

/** The Climates tab in Nerd mode: how each climate is built, and how well each would have planned. */
const NerdClimates: TOC<{ Args: { years: string } }> = <template>
  <section id="climates">
    <h2>Climates</h2>
    <p>
      Each climate is a grid of monthly values (highs, lows, rain, rainy days at
      1, 5 and 10 mm) on 0.25° cells, turned into seasonal curves for the app
      (see Data). 15 yrs is the base; every other climate is 15 yrs plus a
      correction, so where nothing changes it is the same, byte for byte.
    </p>

    <h3>15 yrs</h3>
    <p>
      The average of each month over
      {{@years}}
      from ERA5-Land, highs and lows calibrated against CRU TS station data (see
      Data), then brought forward for the warming.
    </p>

    <h3>The warming</h3>
    <p>
      An average of past years describes their middle year: 15 yrs is centred on
      2018. So every climate's highs and lows are brought forward to the year
      after its period, 2026, by
    </p>
    <ul>
      <li><strong>the rate:</strong>
        each cell's straight-line trend of the year's average high (low) over
        1981–2025, averaged over 21° × 21° of land around it;</li>
      <li><strong>times the years ahead:</strong>
        from the middle of the climate's years to 2026 (8 for 15 yrs and El Niño
        and La Niña, 5.5 for 10 yrs, 3 for 5 yrs). 1 yr is the real 2025, and
        stays as it was.</li>
    </ul>
    <p>
      Why so broad: a single cell's trend is too noisy to use. Backtested
      (below), each cell's own trend made the forecasts worse than no
      correction; the broad one made them better. Rain isn't brought forward, as
      its trends didn't help. The correction is applied when the curves are
      packed, so it adds nothing to the download.
    </p>

    <h3>10 yrs, 5 yrs, 1 yr</h3>
    <p>
      The correction is the window's average minus the average of
      {{@years}}, both measured on the same ERA5-Land months:
    </p>
    <ul>
      <li><strong>Highs and lows:</strong>
        the difference in °C is added.</li>
      <li><strong>Rain:</strong>
        multiplied by the ratio of the two averages, between 0.5 and 2 (for 1
        yr, between 0 and 10, as a real month can be dry or soaked); months with
        under 1 mm keep their rain.</li>
      <li><strong>Rainy days:</strong>
        the difference in days is added, kept within the month, and days over 10
        mm never outnumber days over 5 mm, nor those days over 1 mm.</li>
    </ul>

    <h3>El Niño and La Niña</h3>
    <ol>
      <li><strong>Which months:</strong>
        from NOAA's Oceanic Niño Index, a month is El Niño (La Niña) when it
        lies in a run of at least 5 overlapping three-month seasons at +0.5 °C
        or more (−0.5 °C or less), over 1981–2025.</li>
      <li><strong>Departures:</strong>
        for each cell and month of the year, each year's value minus that cell's
        straight-line trend over 1981–2025, so recent warming isn't mistaken for
        El Niño just because recent years had more of them.</li>
      <li><strong>The correction:</strong>
        the average departure over the event's months, kept only where it beats
        chance: the same average over 100 random sets of as many years is worked
        out, and the correction is kept in full where it's larger than 90% of
        them, fading to nothing at 75%. A month seen in fewer than 2 events gets
        none. Then it's smoothed over 3 × 3 cells and applied as above.</li>
      <li><strong>Checks:</strong>
        the build stops if a well-known effect comes out the wrong way round, if
        an area's average high moves implausibly, or if any cell's highs or lows
        move by more than 6 °C (15 °C for 1 yr; the Tibetan Plateau, with a
        known flaw in the data, has its own limit).</li>
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
        years), each climate is made of the years before it (the last 15, 10 or
        5, or just the last one) and compared with that year's real months, in
        every land cell.
      </p>
      <ul>
        <li><strong>Why these years:</strong>
          the data starts in 1981 and 15 yrs needs 15 years before the year it's
          tested on, so 1996 is the first; 2025 the last there is.</li>
        <li><strong>The sample is the years.</strong>
          Neighbouring cells and months share their weather, so counting
          millions of cell-months would make the results look far more certain
          than they are. One year's weather says little about the next, so the
          years are close to independent.</li>
        <li><strong>How precise:</strong>
          each error comes with a 95% interval, from resampling the years 2,000
          times (bootstrap): the narrower, the more certain.</li>
        <li><strong>The truth is the real year,</strong>
          not 15 yrs: every climate is scored against what then happened. 15 yrs
          is only the column the others are set against. The warming is in the
          test too: 1996–2025 warmed steadily, so a plain average of past years
          lags behind, 15 yrs by 8 years of warming. Each climate is brought
          forward, from the years before the tested one only; fewer years lag
          less to start with but are noisier. The tables show which wins.</li>
        <li><strong>Telling two climates apart:</strong>
          the climates are compared year by year (the same weather tests both),
          which is far more precise than comparing their two intervals. Only
          where the interval of the difference leaves out 0 is one better or
          worse.</li>
        <li><strong>Raw ERA5-Land:</strong>
          the test uses the uncalibrated monthly values, the same for every
          climate, so it compares the choice of years, not the calibration.</li>
      </ul>
      <p>
        The warming correction is tested the same way, each year's rate from the
        years before it only:
      </p>
      <WarmingTable @measurements={{m}} @area="Europe" />
      <WarmingTable @measurements={{m}} @area="World" />
      <BacktestTable @measurements={{m}} @area="Europe" />
      <VersusTable @measurements={{m}} @area="Europe" />
      <BacktestTable @measurements={{m}} @area="World" />
      <VersusTable @measurements={{m}} @area="World" />
    </Measured>
  </section>
</template>;

export default NerdClimates;
