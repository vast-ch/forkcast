import { module, test } from 'qunit';
import { tileArea, tileId, tilesAlong, tilesIn } from 'forkcast/utils/climate';

module('Unit | Utility | climate tiles', function () {
  test('a point is in the tile of its south-west corner', function (assert) {
    assert.strictEqual(tileId(46.7, 7.9), '40_0', 'Interlaken');
    assert.strictEqual(tileId(-33.9, 151.2), '-40_150', 'Sydney');
    assert.strictEqual(
      tileId(50, 10),
      '50_10',
      'an edge belongs to the tile north and east of it',
    );
    assert.strictEqual(tileId(64.7, -147.7), '60_-150', 'Fairbanks');
    assert.strictEqual(tileId(65, 185), '60_-180', 'east of 180° wraps round');
  });

  test('a box covers every tile it touches', function (assert) {
    assert.deepEqual(
      tilesIn([
        [45, 5],
        [52, 21],
      ]),
      ['40_0', '40_10', '40_20', '50_0', '50_10', '50_20'],
    );
    assert.deepEqual(
      tilesIn([
        [60, 175],
        [65, 185],
      ]),
      ['60_170', '60_-180'],
      'across 180°',
    );
  });

  test('a route needs the tiles it passes through, once each', function (assert) {
    const points = [
      { lat: 46.7, lon: 7.9 },
      { lat: 45, lon: 9 },
      { lat: 41.4, lon: 2.2 },
      { lat: 36.7, lon: -4.4 },
    ];
    assert.deepEqual(tilesAlong({ points }), ['40_0', '30_-10']);
  });

  test('a tile owns its square', function (assert) {
    assert.deepEqual(tileArea('-40_150'), [
      [-40, 150],
      [-30, 160],
    ]);
  });
});
