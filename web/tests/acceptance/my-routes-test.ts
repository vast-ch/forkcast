import { module, test } from 'qunit';
import { click, currentURL, fillIn, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
import { button, field } from 'forkcast/tests/helpers/find';
import { encodeTrack } from 'forkcast/utils/route';

const BERN = { lat: 46.95, lon: 7.45 };
const LUCERNE = { lat: 47.05, lon: 8.31 };
const ZURICH = { lat: 47.37, lon: 8.54 };
const UUID = /route=([0-9a-f-]{36})/;

module('Acceptance | my routes', function (hooks) {
  setupApplicationTest(hooks);

  /** Draw a route through `points` and save it. Clicks on the map land where
   * Leaflet puts them, so the points go to the planner directly. */
  async function draw(
    owner: { lookup(name: 'service:planner'): unknown },
    points: { lat: number; lon: number }[],
  ) {
    await click(button('Draw a route'));
    const planner = owner.lookup('service:planner') as {
      addDrawnPoint(lat: number, lon: number): void;
    };
    for (const p of points) planner.addDrawnPoint(p.lat, p.lon);
    await click(button('Save route'));
  }

  test('a drawn route is saved with a name and the link points to it', async function (assert) {
    await visit('/');
    await draw(this.owner, [BERN, LUCERNE]);

    assert.dom('#route-picker option:checked').includesText('Route 1');
    assert.dom(field('Name')).hasValue('Route 1');
    assert.ok(UUID.test(currentURL()), currentURL());
    assert.dom('.wt-summary').exists('the trip is planned');
  });

  test('several routes, each renamed, picked and deleted on its own', async function (assert) {
    await visit('/');
    await draw(this.owner, [BERN, LUCERNE]);
    await fillIn(field('Name'), 'To Lucerne');
    await draw(this.owner, [LUCERNE, ZURICH]);
    await fillIn(field('Name'), 'To Zürich');

    const mine = () =>
      [
        ...document.querySelectorAll(
          '#route-picker optgroup[label="Your routes"] option',
        ),
      ].map((o) => o.textContent.split(' · ')[0]);
    assert.deepEqual(mine(), ['To Lucerne', 'To Zürich']);

    const first = document.querySelector<HTMLOptionElement>(
      '#route-picker optgroup[label="Your routes"] option',
    )!;
    await fillIn('#route-picker', first.value);
    assert.dom(field('Name')).hasValue('To Lucerne');

    await click(button('Delete this route'));
    assert.deepEqual(mine(), ['To Zürich']);
    assert
      .dom('#route-picker option:checked')
      .includesText('Interlaken – Málaga');
  });

  test('a drawn route can be drawn further', async function (assert) {
    await visit('/');
    await draw(this.owner, [BERN, LUCERNE]);
    const km = () =>
      document.querySelector('#route-picker option:checked')!.textContent;
    const before = km();

    await click(button('Edit route'));
    assert.dom('[aria-label="Drawing a route"]').exists();
    const planner = this.owner.lookup('service:planner');
    assert.strictEqual(
      planner.sketch.length,
      2,
      'it carries on from the saved clicks',
    );
    planner.addDrawnPoint(ZURICH.lat, ZURICH.lon);
    await click(button('Save route'));

    assert
      .dom('#route-picker optgroup[label="Your routes"] option')
      .exists({ count: 1 });
    assert.notStrictEqual(km(), before, 'longer now');
    assert.dom(field('Name')).hasValue('Route 1');
  });

  test('a link to a route saved in another browser warns', async function (assert) {
    await visit('/?route=0b5e2d6c-4f1a-4c3e-9d2b-7a8f6e5d4c3b');
    assert
      .dom('[role="alert"]')
      .includesText('saved only in the browser where they were made');
    assert.dom('#route-picker option:checked').hasText('Route not saved here');
    assert.dom('.wt-summary').doesNotExist();
  });

  test('an old link carrying the route saves it to your routes', async function (assert) {
    const track = encodeTrack([BERN, LUCERNE, ZURICH]);
    await visit(`/?track=${encodeURIComponent(track)}&name=Old%20link`);

    assert.dom('#route-picker option:checked').includesText('Old link');
    assert.ok(UUID.test(currentURL()), currentURL());
    assert.notOk(currentURL().includes('track='), 'the track leaves the link');

    // The same old link again doesn't save it twice.
    await visit(`/?track=${encodeURIComponent(track)}&name=Old%20link`);
    assert
      .dom('#route-picker optgroup[label="Your routes"] option')
      .exists({ count: 1 });
  });

  test('imported routes have no Edit route (only rename and delete)', async function (assert) {
    const track = encodeTrack([BERN, ZURICH]);
    await visit(`/?track=${encodeURIComponent(track)}`);
    assert.dom(field('Name')).exists();
    assert.throws(() => button('Edit route'));
    assert.dom(button('Delete this route')).exists();
  });
});
