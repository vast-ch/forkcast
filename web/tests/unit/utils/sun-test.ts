import { module, test } from 'qunit';
import { daylightHours } from 'forkcast/utils/sun';

const at = (iso: string) => new Date(`${iso}T12:00:00`);
const here = (lat: number, lon: number) => ({ lat, lon });
/** Published day lengths (timeanddate.com), in hours. */
const hm = (h: number, m: number) => h + m / 60;

module('Unit | Utility | sun', function () {
  for (const [name, date, p, expected] of [
    ['Zürich, midsummer', '2026-06-21', here(47.37, 8.54), hm(15, 58)],
    ['Zürich, midwinter', '2026-12-21', here(47.37, 8.54), hm(8, 27)],
    ['London, midwinter', '2026-12-21', here(51.51, -0.13), hm(7, 50)],
    ['the equator, equinox', '2026-03-20', here(0, 30), hm(12, 7)],
  ] as const) {
    test(`daylight in ${name} is within 3 minutes of published tables`, function (assert) {
      const got = daylightHours(at(date), p, p);
      assert.true(Math.abs(got - expected) < 3 / 60, `${got} vs ${expected}`);
    });
  }

  test('it is 24 hours under the midnight sun and 0 in the polar night', function (assert) {
    const nordkapp = here(71.17, 25.78);
    assert.strictEqual(daylightHours(at('2026-06-21'), nordkapp, nordkapp), 24);
    assert.strictEqual(daylightHours(at('2026-12-21'), nordkapp, nordkapp), 0);
  });

  test('it is longer riding west, where the sun sets later', function (assert) {
    const east = here(46.2, 7.0);
    const west = here(46.0, 6.0);
    const date = at('2026-10-26');
    assert.true(
      daylightHours(date, east, west) > daylightHours(date, east, east),
    );
  });
});
