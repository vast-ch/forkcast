import { module, test } from 'qunit';
import { setupTest } from 'forkcast/tests/helpers';
import { isOwnRouteId } from 'forkcast/services/my-routes';
import { decodeTrack } from 'forkcast/utils/route';

const line = [
  { lat: 46.95, lon: 7.45, ele: 540 },
  { lat: 47.05, lon: 8.31, ele: 435 },
];

module('Unit | Service | my-routes', function (hooks) {
  setupTest(hooks);

  test('it keeps routes in browser storage, whole and with their names', function (assert) {
    const routes = this.owner.lookup('service:my-routes');
    const saved = routes.add(line, 'Lake ride');
    assert.true(isOwnRouteId(saved.id));
    assert.deepEqual(decodeTrack(saved.track), line, 'no point lost');

    // A fresh service (as after a reload) reads them back.
    const fresh = this.owner.factoryFor('service:my-routes').create();
    assert.deepEqual(
      fresh.routes.map((r) => r.name),
      ['Lake ride'],
    );
  });

  test('it names drawn routes in turn and keeps names unique', function (assert) {
    const routes = this.owner.lookup('service:my-routes');
    assert.strictEqual(routes.nextName(), 'Route 1');
    routes.add(line, '');
    assert.strictEqual(routes.routes[0]!.name, 'Route 1');
    assert.strictEqual(routes.nextName(), 'Route 2');
  });

  test('it renames, redraws and removes', function (assert) {
    const routes = this.owner.lookup('service:my-routes');
    const { id } = routes.add(line, 'A', { sketch: line, snap: true });
    routes.rename(id, 'B');
    routes.redraw(
      id,
      [...line, { lat: 47.37, lon: 8.54, ele: 408 }],
      line,
      false,
    );
    const r = routes.find(id)!;
    assert.strictEqual(r.name, 'B');
    assert.strictEqual(decodeTrack(r.track).length, 3);
    assert.false(r.snap);
    routes.remove(id);
    assert.strictEqual(routes.find(id), undefined);
  });

  test('it tells preset ids from your route ids', function (assert) {
    assert.false(isOwnRouteId('ev5'));
    assert.true(isOwnRouteId(crypto.randomUUID()));
  });
});
