import { module, test } from 'qunit';
import { WEEKS, weekOfDate } from 'forkcast/utils/weeks';

module('Unit | Utility | weeks', function () {
  test('it splits the year into 48 quarter-months of 7 or 8 days', function (assert) {
    assert.strictEqual(WEEKS.length, 48);
    assert.true(WEEKS.every((w) => w.days === 7 || w.days === 8));
    assert.strictEqual(WEEKS[0]!.label, '1–7 Jan');
  });

  test('it finds the quarter-month of a date', function (assert) {
    assert.strictEqual(weekOfDate(new Date(2026, 0, 1)), 0);
    assert.strictEqual(weekOfDate(new Date(2026, 0, 31)), 3);
    assert.strictEqual(weekOfDate(new Date(2026, 11, 31)), 47);
  });
});
