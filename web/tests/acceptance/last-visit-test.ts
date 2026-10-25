import { module, test } from 'qunit';
import { currentURL, visit } from '@ember/test-helpers';
import {
  setupApplicationTest,
  storeAsApp,
  storedByApp,
} from 'forkcast/tests/helpers';
import { closeTo } from 'forkcast/tests/helpers/close-to';
import type LastVisitService from 'forkcast/services/last-visit';

module('Acceptance | last visit', function (hooks) {
  setupApplicationTest(hooks);

  /** What an earlier visit left in storage. */
  function leftAt(plan: string, view?: typeof VIEW) {
    storeAsApp('last-plan', plan);
    if (view) storeAsApp('map-view', view);
  }
  const VIEW = { lat: 41.5, lon: 2.5, zoom: 7 };
  const savedView = (owner: { lookup(name: string): unknown }) =>
    (owner.lookup('service:last-visit') as LastVisitService).view;

  test('opening Forkcast with nothing in the address picks up the last settings', async function (assert) {
    leftAt('km=120&speed=18');
    await visit('/');

    assert.ok(currentURL().includes('km=120'), currentURL());
    assert.ok(currentURL().includes('speed=18'), currentURL());
  });

  test('a link with settings opens what it says, and is remembered', async function (assert) {
    leftAt('km=120');
    await visit('/?km=90');
    assert.notOk(currentURL().includes('km=120'), currentURL());
    assert.strictEqual(storedByApp('last-plan'), 'km=90');
  });

  test('the map opens where it was left instead of fitting the route', async function (assert) {
    leftAt('', VIEW);
    await visit('/');
    // Leaflet puts the centre on a whole pixel, ~0.01° at this zoom.
    const view = savedView(this.owner)!;
    closeTo(assert, view.lat, VIEW.lat, 1);
    closeTo(assert, view.lon, VIEW.lon, 1);
    assert.strictEqual(view.zoom, VIEW.zoom);
  });

  test('a link with settings fits its route instead', async function (assert) {
    leftAt('', VIEW);
    await visit('/?km=100');
    assert.notDeepEqual(savedView(this.owner), VIEW);
  });
});
