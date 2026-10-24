import { module, test } from 'qunit';
import {
  fmtDaylight,
  fmtHours,
  fmtKm,
  fmtMm,
  fmtTemp,
} from 'forkcast/utils/format';

module('Unit | Utility | format', function () {
  test('it writes units next to the numbers', function (assert) {
    assert.strictEqual(fmtTemp(14.6), '15°C');
    assert.strictEqual(fmtTemp(Number.NaN), '–');
    assert.strictEqual(fmtMm(4.94), '4.9mm');
    assert.strictEqual(fmtMm(23.4), '23mm');
    assert.strictEqual(fmtKm(80), '80.0km');
    assert.strictEqual(fmtKm(2369.4), `${(2369).toLocaleString()}km`);
    assert.strictEqual(fmtHours(3.81), '3h 49min');
  });

  test('it names the polar extremes of daylight', function (assert) {
    assert.strictEqual(fmtDaylight(24), '24h (midnight sun)');
    assert.strictEqual(fmtDaylight(0), 'None (polar night)');
    assert.strictEqual(fmtDaylight(10.4), '10h 24min');
  });
});
