import { module, test } from 'qunit';
import { haversineKm, lineKm } from 'forkcast/utils/geo';
import { closeTo } from 'forkcast/tests/helpers/close-to';

module('Unit | Utility | geo', function () {
  test('it measures great-circle distances in km', function (assert) {
    // Bern to Zürich, about 95 km as the crow flies.
    closeTo(
      assert,
      haversineKm({ lat: 46.948, lon: 7.447 }, { lat: 47.377, lon: 8.54 }),
      95.5,
      0,
    );
    // A degree of latitude is about 111.2 km.
    closeTo(
      assert,
      haversineKm({ lat: 0, lon: 0 }, { lat: 1, lon: 0 }),
      111.2,
      1,
    );
  });

  test('it adds up the length of a line', function (assert) {
    const line = [0, 1, 2].map((lat) => ({ lat, lon: 0 }));
    closeTo(assert, lineKm(line), 2 * 111.195, 1);
    assert.strictEqual(lineKm(line.slice(0, 1)), 0);
  });
});
