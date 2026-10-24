import { module, test } from 'qunit';
import { click, currentURL, fillIn, findAll, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
import { button, field } from 'forkcast/tests/helpers/find';

/** The summary's value for a label, e.g. "Days". */
const summary = (label: string) =>
  findAll('.wt-summary div')
    .find((d) => d.querySelector('dt')?.textContent?.trim() === label)
    ?.querySelector('dd')
    ?.textContent?.trim();

module('Acceptance | planner', function (hooks) {
  setupApplicationTest(hooks);

  test('it opens on the default route with a trip summary', async function (assert) {
    await visit('/');
    assert.strictEqual(currentURL(), '/');
    assert
      .dom('#route-picker option:checked')
      .includesText('Interlaken – Málaga');
    assert.ok(Number(summary('Days')) > 0, 'the trip has days');
    assert.dom('[aria-label="Weather by day"]').exists('the day chart shows');
  });

  test('trip settings go into the URL and change the trip', async function (assert) {
    await visit('/');
    const days = Number(summary('Days'));
    await fillIn(field('km per day'), '160');
    assert.strictEqual(currentURL(), '/?km=160');
    assert.true(Number(summary('Days')) < days, 'longer days, fewer of them');
  });

  test('settings in the URL are read back', async function (assert) {
    await visit('/?km=160&rest=0');
    assert.dom(field('km per day')).hasValue('160');
    assert.strictEqual(summary('Rest days'), '0');
  });

  test('map details switch their layers on and off', async function (assert) {
    await visit('/');
    await click(button('Cities'));
    assert.strictEqual(currentURL(), '/?cities=false');
    assert.dom('.leaflet-labels-pane .wt-place').doesNotExist();
    await click(button('Cities'));
    assert.strictEqual(currentURL(), '/');
    assert.dom('.leaflet-labels-pane .wt-place').exists();
  });

  test('cancel leaves the route as it was', async function (assert) {
    await visit('/');
    await click(button('Draw a route'));
    await click(button('Cancel'));
    assert.dom('[aria-label="Drawing a route"]').doesNotExist();
    assert
      .dom('#route-picker option:checked')
      .includesText('Interlaken – Málaga');
  });
});
