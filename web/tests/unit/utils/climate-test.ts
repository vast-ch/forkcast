import { module, test } from 'qunit';
import ClimateGrid, {
  type ClimateHeader,
  type Encoding,
  type GridGeometry,
} from 'forkcast/utils/climate';
import { closeTo } from 'forkcast/tests/helpers/close-to';

/** One cell, at 47° N 8° E. */
const CELL: GridGeometry = { lon0: 8, lat0: 47, step: 0.25, cols: 1, rows: 1 };

/** No seasonal waves: every term after the mean decodes to 0. */
const FLAT: Encoding = { kind: 'linear', scale: 1, offset: 0 };

/**
 * A one-cell grid with the same weather all year: `pre` mm of rain a day and
 * a share `r1` of days with rain.
 */
function grid(pre: number, r1: number): ClimateGrid {
  const curve = (mean: Encoding): Encoding[] => [
    mean,
    ...Array<Encoding>(6).fill(FLAT),
  ];
  const header: ClimateHeader = {
    source: 'test',
    years: [2011, 2025],
    step: 0.25,
    tile: 10,
    size: 1,
    tiles: [],
    overview: CELL,
    dtype: 'u8',
    vars: ['tmx', 'tmn', 'pre', 'r1', 'r5', 'r10'],
    terms: 7,
    encoding: {
      tmx: curve({ kind: 'linear', scale: 2, offset: -64 }),
      tmn: curve({ kind: 'linear', scale: 2, offset: -64 }),
      pre: curve({ kind: 'sqrt', scale: 40 }),
      r1: curve({ kind: 'linear', scale: 200, offset: 0 }),
      r5: curve({ kind: 'linear', scale: 200, offset: 0 }),
      r10: curve({ kind: 'linear', scale: 200, offset: 0 }),
    },
    nodata: 255,
  };
  const means = [168, 148, Math.sqrt(pre) * 40, r1 * 200, 0, 0];
  const data = new Uint8Array(means.flatMap((m) => [m, 0, 0, 0, 0, 0, 0]));
  return new ClimateGrid(header, CELL, data.buffer);
}

module('Unit | Utility | climate', function () {
  test('a wet day brings the rain over its days with rain', function (assert) {
    // 2.25 mm a day, rain on a quarter of the days: 9 mm each, whatever the threshold.
    const g = grid(2.25, 0.25);
    for (const threshold of [1, 5, 10]) {
      const w = g.at(0.5, 47, 8, threshold);
      closeTo(assert, w.wetDayMm, 9, 0.1, `at ${threshold} mm`);
    }
    const w = g.at(0.5, 47, 8, 1);
    closeTo(assert, w.wetDayMm * w.rainChance, w.rainMm, 0.01);
  });

  test('where it hardly ever rains, there is no rain per wet day', function (assert) {
    assert.true(Number.isNaN(grid(0, 0).at(0.5, 47, 8, 1).wetDayMm));
  });
});
