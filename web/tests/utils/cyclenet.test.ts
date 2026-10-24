import { describe, expect, it } from 'vitest';
import { CycleNet } from 'forkcast/utils/cyclenet';

// A small network around 50°N: one route east along the latitude, and a
// second one north from it that stops 500 m short (as OSM sections often do).
const east: [number, number][] = [
  [0, 50],
  [0.1, 50],
  [0.2, 50],
  [0.3, 50],
];
const north: [number, number][] = [
  [0.2, 50.005],
  [0.2, 50.1],
  [0.2, 50.2],
];
const net = (lines: [number, number][][]) => new CycleNet([{ lines }]);

describe('CycleNet', () => {
  it('snaps onto the line itself, not only its corners', () => {
    const s = net([east]).snap({ lat: 50.01, lon: 0.15 }, 2)!;
    expect(s.point.lon).toBeCloseTo(0.15, 3);
    expect(s.point.lat).toBeCloseTo(50, 3);
    expect(s.away).toBeCloseTo(1.11, 1);
  });

  it('finds nothing beyond the reach', () => {
    expect(net([east]).snap({ lat: 50.5, lon: 0.15 }, 2)).toBeUndefined();
  });

  it('links a dead end to a route within 1 km, so they route through', () => {
    const n = net([east, north]);
    const from = n.snap({ lat: 50, lon: 0 }, 1)!;
    const to = n.snap({ lat: 50.2, lon: 0.2 }, 1)!;
    const path = n.route(from, to)!;
    expect(path).toBeDefined();
    expect(path[path.length - 1]!.lat).toBeCloseTo(50.2, 3);
  });

  it('follows the routes between clicks', () => {
    const line = net([east, north]).match(
      [
        { lat: 50, lon: 0 },
        { lat: 50.2, lon: 0.2 },
      ],
      25,
    );
    // Along the east route to 0.2°, then up the north one: not a straight line.
    expect(line.some((p) => p.lat === 50 && p.lon === 0.2)).toBe(true);
    expect(line.length).toBeGreaterThan(3);
  });

  it('goes straight where there is no route near a click', () => {
    const sketch = [
      { lat: 50, lon: 0 },
      { lat: 52, lon: 3 },
    ];
    const line = net([east]).match(sketch, 25);
    expect(line[line.length - 1]).toEqual(sketch[1]);
  });

  it('goes straight instead of a big detour', () => {
    // Two points 1 km apart on a route that only connects them via a 60 km loop.
    const loop: [number, number][] = [
      [0, 50],
      [0, 50.3],
      [0.014, 50.3],
      [0.014, 50],
    ];
    const line = net([loop]).match(
      [
        { lat: 50, lon: 0 },
        { lat: 50, lon: 0.014 },
      ],
      1,
    );
    expect(line).toHaveLength(2);
  });
});
