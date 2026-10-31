import type { TOC } from '@ember/component/template-only';
import { CLIMATE_CHOICES } from 'forkcast/services/planner';
import {
  fmtMeasured,
  measured,
  type Measurement,
  type Measurements,
} from 'forkcast/utils/verify';

const label = (id: string) =>
  CLIMATE_CHOICES.find((c) => c.value === id)?.label ?? id;

const MONTHS = 'Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(' ');
const FIELDS = [
  { id: 'tmx', label: 'Highs' },
  { id: 'tmn', label: 'Lows' },
  { id: 'pre', label: 'Rain' },
  { id: 'r5', label: 'Rainy days' },
];
const AREAS = ['Europe', 'World'];

/** One stat of a backtest row, or undefined. */
function stat(
  m: Measurements,
  climate: string,
  field: string,
  area: string,
  name: string,
) {
  return measured(m, { metric: 'backtest', climate, field, area, stat: name });
}

/** The plain 15-year average, kept in the backtest to measure the warming correction (WarmingTable). */
const UNSHIFTED = 'last15 unshifted';

const climatesIn = (m: Measurements, area: string) => [
  ...new Set(
    m.results
      .filter(
        (r) =>
          r.metric === 'backtest' && r.area === area && r.climate !== UNSHIFTED,
      )
      .map((r) => r.climate),
  ),
];

/** Each climate's average error per field, with its 95 % interval. */
function backtest(m: Measurements, area: string) {
  return climatesIn(m, area).map((c) => ({
    label: label(c),
    cells: FIELDS.map((f) => {
      const [v, lo, hi] = ['mae', 'mae lo95', 'mae hi95'].map((s) =>
        stat(m, c, f.id, area, s),
      );
      return {
        text: fmtMeasured(v),
        range: lo && hi ? `${fmtMeasured(lo)} to ${fmtMeasured(hi)}` : '',
      };
    }),
  }));
}

/**
 * Each other climate against 15 yrs, year by year: the difference in error
 * with its interval, the share of years it did worse, and a verdict that only
 * calls it better or worse when the interval leaves out 0.
 */
function versus(m: Measurements, area: string) {
  return climatesIn(m, area)
    .filter((c) => c !== 'last15')
    .map((c) => ({
      label: label(c),
      cells: FIELDS.map((f) => {
        const [d, lo, hi, worse] = [
          'vs last15',
          'vs last15 lo95',
          'vs last15 hi95',
          'worse years',
        ].map((s) => stat(m, c, f.id, area, s));
        const verdict =
          !lo || !hi
            ? ''
            : lo.value > 0
              ? 'worse'
              : hi.value < 0
                ? 'better'
                : 'no difference';
        return {
          text: fmtMeasured(d, true),
          range:
            lo && hi
              ? `${fmtMeasured(lo, true)} to ${fmtMeasured(hi, true)}`
              : '',
          worse: worse
            ? `worse in ${Math.round(worse.value * 100)}% of years`
            : '',
          verdict,
        };
      }),
    }));
}

/** 15 yrs brought forward for the warming against the plain average, highs and lows. */
function warming(m: Measurements, area: string) {
  return FIELDS.slice(0, 2).map((f) => {
    const get = (c: string, name: string) => stat(m, c, f.id, area, name);
    const ci = (c: string, name: string) => {
      const [v, lo, hi] = [name, `${name} lo95`, `${name} hi95`].map((n) =>
        get(c, n),
      );
      return {
        text: fmtMeasured(v, name === 'bias'),
        range:
          lo && hi
            ? `${fmtMeasured(lo, name === 'bias')} to ${fmtMeasured(hi, name === 'bias')}`
            : '',
      };
    };
    const worse = get(UNSHIFTED, 'worse years');
    return {
      label: f.label,
      cells: [
        ci('last15', 'bias'),
        ci(UNSHIFTED, 'bias'),
        ci('last15', 'mae'),
        ci(UNSHIFTED, 'mae'),
        {
          text: worse ? fmtMeasured({ ...worse, value: 1 - worse.value }) : '',
          range: '',
        },
      ],
    };
  });
}

/** The first and last year the climates were tested on. */
export const backtestFrom = (m: Measurements) => m.backtest[0];
export const backtestTo = (m: Measurements) => m.backtest[1];

/** How many years each climate was tested on. */
export const backtestYears = (m: Measurements) =>
  measured(m, { metric: 'backtest', stat: 'years' })?.value ?? 0;

/** The El Niño and La Niña corrections where their effect is well known, and whether each points the right way. */
function enso(m: Measurements) {
  const rows = m.results.filter(
    (r) => r.metric === 'enso' && r.stat.startsWith('mean'),
  );
  return rows.map((r: Measurement) => {
    const sign = measured(m, {
      metric: 'enso',
      climate: r.climate,
      field: r.field,
      area: r.area,
      stat: 'expected sign',
    })?.value;
    const months = r.stat
      .replace('mean ', '')
      .split('+')
      .map((n) => MONTHS[Number(n) - 1])
      .join(', ');
    const what = r.field === 'pre' ? 'rain' : 'highs';
    return {
      climate: label(r.climate),
      where: `${r.area}, ${months}`,
      expected: `${sign && sign > 0 ? 'more' : 'less'} ${what}`,
      value: fmtMeasured(r, true),
      isRight: sign !== undefined && Math.sign(r.value) === sign,
    };
  });
}

/** How far each other climate moves the year's average high, per area. */
function shifts(m: Measurements) {
  const rows = m.results.filter((r) => r.metric === 'shift');
  const climates = [...new Set(rows.map((r) => r.climate))];
  return climates.map((c) => ({
    label: label(c),
    cells: AREAS.map((a) =>
      fmtMeasured(
        rows.find((r) => r.climate === c && r.area === a),
        true,
      ),
    ),
  }));
}

/** The backtest of 15, 10, 5 and 1 yr as forecasts of the following year. */
export const BacktestTable: TOC<{
  Args: { measurements: Measurements; area: string };
}> = <template>
  <table class="wt-help-table">
    <caption>{{@area}}: a month's average error as a forecast of the following
      year, with its 95% interval</caption>
    <thead><tr><th scope="col">Climate</th>
        {{#each FIELDS as |f|}}<th scope="col">{{f.label}}</th>{{/each}}
      </tr></thead>
    <tbody>
      {{#each (backtest @measurements @area) as |row|}}
        <tr><th scope="row">{{row.label}}</th>
          {{#each row.cells as |c|}}
            <td>{{c.text}}<small>{{c.range}}</small></td>
          {{/each}}
        </tr>
      {{/each}}
    </tbody>
  </table>
</template>;

/** What bringing 15 yrs forward for the warming changes, tested on the following years. */
export const WarmingTable: TOC<{
  Args: { measurements: Measurements; area: string };
}> = <template>
  <table class="wt-help-table">
    <caption>{{@area}}: 15 yrs brought forward, and the plain average, as a
      forecast of the following year (an average error below 0 is too cold)</caption>
    <thead><tr><th scope="col"></th><th scope="col">Average error</th><th
          scope="col"
        >Plain average</th><th scope="col">Typical error</th><th
          scope="col"
        >Plain average</th><th scope="col">Years closer</th></tr></thead>
    <tbody>
      {{#each (warming @measurements @area) as |row|}}
        <tr><th scope="row">{{row.label}}</th>
          {{#each row.cells as |c|}}
            <td>{{c.text}}<small>{{c.range}}</small></td>
          {{/each}}
        </tr>
      {{/each}}
    </tbody>
  </table>
</template>;

/** Each climate against 15 yrs, compared year by year. */
export const VersusTable: TOC<{
  Args: { measurements: Measurements; area: string };
}> = <template>
  <table class="wt-help-table">
    <caption>{{@area}}: the error compared with 15 yrs, year by year (more is
      worse)</caption>
    <thead><tr><th scope="col">Climate</th>
        {{#each FIELDS as |f|}}<th scope="col">{{f.label}}</th>{{/each}}
      </tr></thead>
    <tbody>
      {{#each (versus @measurements @area) as |row|}}
        <tr><th scope="row">{{row.label}}</th>
          {{#each row.cells as |c|}}
            <td data-verdict={{c.verdict}}>{{c.text}}
              <small>{{c.range}}</small>
              <small>{{c.worse}}</small>
              <small class="wt-help-verdict">{{c.verdict}}</small></td>
          {{/each}}
        </tr>
      {{/each}}
    </tbody>
  </table>
</template>;

/** The known ENSO effects, as the El Niño and La Niña climates change them. */
export const EnsoTable: TOC<{ Args: { measurements: Measurements } }> =
  <template>
    <table class="wt-help-table">
      <caption>Where the effect is well known: the climate's change from 15 yrs,
        averaged over the region and months</caption>
      <thead><tr><th scope="col">Climate</th><th scope="col">Where, when</th><th
            scope="col"
          >Expected</th><th scope="col">Change</th><th scope="col">Right way?</th></tr></thead>
      <tbody>
        {{#each (enso @measurements) as |row|}}
          <tr><th scope="row">{{row.climate}}</th><td>{{row.where}}</td><td
            >{{row.expected}}</td><td>{{row.value}}</td><td>{{if
                row.isRight
                "✓"
                "✗"
              }}</td></tr>
        {{/each}}
      </tbody>
    </table>
  </template>;

/** How far each climate moves the year's average high from 15 yrs. */
export const ShiftTable: TOC<{ Args: { measurements: Measurements } }> =
  <template>
    <table class="wt-help-table">
      <caption>The year's average high, compared with 15 yrs</caption>
      <thead><tr><th scope="col">Climate</th>
          {{#each AREAS as |a|}}<th scope="col">{{a}}</th>{{/each}}
        </tr></thead>
      <tbody>
        {{#each (shifts @measurements) as |row|}}
          <tr><th scope="row">{{row.label}}</th>
            {{#each row.cells as |c|}}<td>{{c}}</td>{{/each}}
          </tr>
        {{/each}}
      </tbody>
    </table>
  </template>;
