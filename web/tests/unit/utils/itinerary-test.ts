import { module, test } from 'qunit';
import { milestones, planTrip } from 'forkcast/utils/itinerary';
import { withDistances } from 'forkcast/utils/route';
import type { ClimateSource, DayClimate } from 'forkcast/utils/climate';
import { closeTo } from 'forkcast/tests/helpers/close-to';

/** The same weather everywhere, always. */
const climate: ClimateSource = {
  years: [2011, 2025],
  covers: () => true,
  at: (): DayClimate => ({
    high: 20,
    low: 10,
    rainMm: 1,
    rainChance: 0.25,
    wetDayMm: 4,
    altitudeShift: 0,
  }),
};
// A straight route east along 46°N, about 460 km.
const route = (() => {
  const points = withDistances(
    Array.from({ length: 61 }, (_, i) => ({
      lat: 46,
      lon: 6 + i * 0.1,
      ele: 500,
    })),
  );
  return {
    id: 'test',
    name: 'Test',
    group: 'Test',
    color: '#000',
    isPreset: false,
    points,
    km: points[points.length - 1]!.km,
  };
})();
const settings = {
  start: '2026-06-01',
  kmPerDay: 100,
  speed: 20,
  rideDays: 2,
  restDays: 1,
  rainThreshold: 5,
};

module('Unit | Utility | itinerary', function () {
  const trip = planTrip(route, climate, settings);

  test('it rides and rests in the pattern, and never ends on a rest day', function (assert) {
    assert.strictEqual(
      trip.days.map((d) => (d.isRest ? 'R' : 'r')).join(''),
      'rrRrrRr',
    );
    assert.false(trip.days[trip.days.length - 1]!.isRest);
    assert.strictEqual(trip.ridingDays, 5);
    assert.strictEqual(trip.restDays, 2);
  });

  test('it covers the route day by day', function (assert) {
    const riding = trip.days.filter((d) => !d.isRest);
    assert.strictEqual(riding[0]!.fromKm, 0);
    closeTo(assert, riding[riding.length - 1]!.toKm, route.km, 5);
    assert.true(
      riding.every((d, i) => i === 0 || d.fromKm === riding[i - 1]!.toKm),
    );
  });

  test('it gives each riding day its riding time and daylight', function (assert) {
    const day = trip.days[0]!;
    closeTo(assert, day.ridingHours, 100 / 20, 5);
    assert.true(day.daylight > 15, 'June in the Alps');
    assert.false(day.needsLights);
    assert.strictEqual(trip.days[2]!.ridingHours, 0, 'a rest day');
  });

  test('it flags days with more riding than daylight', function (assert) {
    const slow = planTrip(route, climate, {
      ...settings,
      start: '2026-12-21',
      speed: 10,
    });
    assert.true(slow.days[0]!.needsLights);
    assert.true(slow.days.filter((d) => d.isRest).every((d) => !d.needsLights));
  });

  test('it adds up the rain chances into expected rainy days', function (assert) {
    closeTo(assert, trip.rainyDays, 5 * 0.25, 5);
  });

  test('it tags the 1st of each month, rest day or not', function (assert) {
    // Ride, ride, rest from 29 June: 1 July is day 3, a rest day.
    const june = planTrip(route, climate, { ...settings, start: '2026-06-29' });
    const tags = milestones(june, 'months');
    assert.deepEqual(
      tags.map((t) => t.day.n),
      [3],
    );
    assert.true(tags[0]!.day.isRest);
    assert.deepEqual(milestones(june, 'off'), []);
  });

  test('it tags the first day of each week of the trip', function (assert) {
    // Every other day a rest day: 9 days, so weeks 1 and 2.
    const trip = planTrip(route, climate, {
      ...settings,
      rideDays: 1,
      restDays: 1,
    });
    assert.deepEqual(
      milestones(trip, 'weeks').map((t) => [t.day.n, t.label]),
      [
        [1, 'Week 1'],
        [8, 'Week 2'],
      ],
    );
  });
});
