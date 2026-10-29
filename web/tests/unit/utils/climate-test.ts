import { module, test } from 'qunit';
import ClimateGrid, { type ClimateHeader } from 'forkcast/utils/climate';
import { closeTo } from 'forkcast/tests/helpers/close-to';

/** A one-cell grid with the same bytes every month: rain `pre` mm and `r1` days with rain. */
function grid(pre: number, r1: number): ClimateGrid {
  const header: ClimateHeader = {
    source: 'test',
    years: [2011, 2025],
    lon0: 8,
    lat0: 47,
    step: 0.25,
    cols: 1,
    rows: 1,
    dtype: 'u8',
    vars: ['tmx', 'tmn', 'pre', 'r1', 'r5', 'r10'],
    encoding: {
      tmx: { kind: 'linear', scale: 2, offset: -64 },
      tmn: { kind: 'linear', scale: 2, offset: -64 },
      pre: { kind: 'sqrt', scale: 8 },
      r1: { kind: 'linear', scale: 8, offset: 0 },
      r5: { kind: 'linear', scale: 8, offset: 0 },
      r10: { kind: 'linear', scale: 8, offset: 0 },
    },
    nodata: 255,
  };
  const bytes = [168, 148, Math.sqrt(pre) * 8, r1 * 8, 0, 0];
  const data = new Uint8Array(bytes.flatMap((b) => Array<number>(12).fill(b)));
  return new ClimateGrid(header, data.buffer);
}

module('Unit | Utility | climate', function () {
  test('a wet day brings the month’s rain over its days with rain', function (assert) {
    // 100 mm over 10 days with rain: 10 mm each, whatever the threshold.
    const g = grid(100, 10);
    for (const threshold of [1, 5, 10]) {
      const w = g.at(0.5, 47, 8, threshold);
      closeTo(assert, w.wetDayMm, 10, 2, `at ${threshold} mm`);
    }
    const w = g.at(0.5, 47, 8, 1);
    closeTo(assert, w.wetDayMm * w.rainChance, w.rainMm, 6);
  });

  test('where it hardly ever rains, there is no rain per wet day', function (assert) {
    assert.true(Number.isNaN(grid(0, 0).at(0.5, 47, 8, 1).wetDayMm));
  });
});
