import { module, test } from 'qunit';
import { countriesFromTopology, type Topology } from 'forkcast/utils/topology';

module('Unit | Utility | topology', function () {
  test('rings are built from shared arcs', function (assert) {
    // Two squares sharing their middle edge (arc 1), at 1° per step.
    const topo: Topology = {
      transform: { scale: [1, 1], translate: [10, 40] },
      arcs: [
        [
          [1, 0],
          [-1, 0],
          [0, 1],
          [1, 0],
        ], // (11,40) → (10,40) → (10,41) → (11,41)
        [
          [1, 1],
          [0, -1],
        ], // the shared edge, (11,41) → (11,40)
        [
          [1, 1],
          [1, 0],
          [0, -1],
          [-1, 0],
        ], // (11,41) → (12,41) → (12,40) → (11,40)
      ],
      objects: {
        countries: {
          geometries: [
            { type: 'Polygon', arcs: [[0, 1]] },
            { type: 'MultiPolygon', arcs: [[[2, ~1]]] },
          ],
        },
      },
    };
    const [west, east] = countriesFromTopology(topo).features;
    assert.deepEqual(west!.geometry.coordinates, [
      [
        [
          [11, 40],
          [10, 40],
          [10, 41],
          [11, 41],
          [11, 40],
        ],
      ],
    ]);
    assert.deepEqual(
      east!.geometry.coordinates[0]![0],
      [
        [11, 41],
        [12, 41],
        [12, 40],
        [11, 40],
        [11, 41],
      ],
      'the shared edge walked backwards',
    );
  });

  test('a ring across 180° stays on its side', function (assert) {
    const topo: Topology = {
      transform: { scale: [1, 1], translate: [0, 0] },
      arcs: [
        [
          [178, 60],
          [1, 0],
          [-358, 0],
          [0, 1],
          [358, 0],
          [-1, -1],
        ],
      ],
      objects: {
        countries: { geometries: [{ type: 'Polygon', arcs: [[0]] }] },
      },
    };
    const ring =
      countriesFromTopology(topo).features[0]!.geometry.coordinates[0]![0]!;
    assert.deepEqual(
      ring.map(([x]) => x),
      [178, 179, 181, 181, 179, 178],
    );
  });
});
