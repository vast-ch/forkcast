import { module, test } from 'qunit';
import { CycleNet } from 'forkcast/utils/cyclenet';
import { closeTo } from 'forkcast/tests/helpers/close-to';

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

module('Unit | Utility | cyclenet', function () {
  test('it snaps onto the line itself, not only its corners', function (assert) {
    const s = net([east]).snap({ lat: 50.01, lon: 0.15 }, 2)!;
    closeTo(assert, s.point.lon, 0.15, 3);
    closeTo(assert, s.point.lat, 50, 3);
    closeTo(assert, s.away, 1.11, 1);
  });

  test('it finds nothing beyond the reach', function (assert) {
    assert.strictEqual(
      net([east]).snap({ lat: 50.5, lon: 0.15 }, 2),
      undefined,
    );
  });

  test('it links a dead end to a route within 1 km, so they route through', function (assert) {
    const n = net([east, north]);
    const from = n.snap({ lat: 50, lon: 0 }, 1)!;
    const to = n.snap({ lat: 50.2, lon: 0.2 }, 1)!;
    const path = n.route(from, to);
    assert.ok(path, 'there is a path');
    closeTo(assert, path![path!.length - 1]!.lat, 50.2, 3);
  });

  test('it follows the routes between clicks', function (assert) {
    const line = net([east, north]).match(
      [
        { lat: 50, lon: 0 },
        { lat: 50.2, lon: 0.2 },
      ],
      25,
    );
    // Along the east route to 0.2°, then up the north one: not a straight line.
    assert.true(line.some((p) => p.lat === 50 && p.lon === 0.2));
    assert.true(line.length > 3);
  });

  test('it goes straight where there is no route near a click', function (assert) {
    const sketch = [
      { lat: 50, lon: 0 },
      { lat: 52, lon: 3 },
    ];
    const line = net([east]).match(sketch, 25);
    assert.deepEqual(line[line.length - 1], sketch[1]);
  });

  test('it goes straight instead of a big detour', function (assert) {
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
    assert.strictEqual(line.length, 2);
  });
});
