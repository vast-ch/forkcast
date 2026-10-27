import { module, test } from 'qunit';
import { inLimits, isIsoDate, isoDate } from 'forkcast/utils/settings';

module('Unit | Utility | settings', function () {
  test('it keeps the trip numbers in range', function (assert) {
    assert.true(inLimits('kmPerDay', 80));
    assert.false(inLimits('kmPerDay', 1000));
    assert.false(inLimits('rideDays', 2.5));
    assert.true(inLimits('speed', 21.5));
    assert.true(inLimits('restDays', 0));
  });

  test('it reads and writes dates as yyyy-mm-dd', function (assert) {
    assert.true(isIsoDate('2026-10-24'));
    assert.false(isIsoDate('24.10.2026'));
    assert.strictEqual(isoDate(new Date(2026, 0, 5)), '2026-01-05');
  });
});
