import { describe, expect, it } from 'vitest';
import { planTrip } from 'forkcast/utils/itinerary';
import { withDistances } from 'forkcast/utils/route';
import type { ClimateSource, DayClimate } from 'forkcast/utils/climate';

/** The same weather everywhere, always. */
const climate: ClimateSource = {
  years: [2011, 2025],
  covers: () => true,
  at: (): DayClimate => ({
    high: 20,
    low: 10,
    rainMm: 1,
    rainChance: 0.25,
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

describe('planTrip', () => {
  const trip = planTrip(route, climate, settings);

  it('rides and rests in the pattern, and never ends on a rest day', () => {
    expect(trip.days.map((d) => (d.isRest ? 'R' : 'r')).join('')).toBe(
      'rrRrrRr',
    );
    expect(trip.days[trip.days.length - 1]!.isRest).toBe(false);
    expect(trip.ridingDays).toBe(5);
    expect(trip.restDays).toBe(2);
  });

  it('covers the route day by day', () => {
    const riding = trip.days.filter((d) => !d.isRest);
    expect(riding[0]!.fromKm).toBe(0);
    expect(riding[riding.length - 1]!.toKm).toBeCloseTo(route.km, 5);
    expect(
      riding.every((d, i) => i === 0 || d.fromKm === riding[i - 1]!.toKm),
    ).toBe(true);
  });

  it('gives each riding day its riding time and daylight', () => {
    const day = trip.days[0]!;
    expect(day.ridingHours).toBeCloseTo(100 / 20, 5);
    expect(day.daylight).toBeGreaterThan(15); // June in the Alps
    expect(day.needsLights).toBe(false);
    expect(trip.days[2]!.ridingHours).toBe(0); // a rest day
  });

  it('flags days with more riding than daylight', () => {
    const slow = planTrip(route, climate, {
      ...settings,
      start: '2026-12-21',
      speed: 10,
    });
    expect(slow.days[0]!.needsLights).toBe(true);
    expect(slow.days.filter((d) => d.isRest).every((d) => !d.needsLights)).toBe(
      true,
    );
  });

  it('adds up the rain chances into expected rainy days', () => {
    expect(trip.rainyDays).toBeCloseTo(5 * 0.25, 5);
  });
});
