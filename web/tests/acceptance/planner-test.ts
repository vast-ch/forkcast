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

  test('rain shows as rainy-day emoji, or as mm dots', async function (assert) {
    await visit('/');
    assert.dom('.wt-legend-emoji').includesText('2+ days');
    await click(button('1mm'));
    assert
      .dom('.wt-legend-emoji')
      .includesText('3+ days', 'steps for 1 mm days');
    assert.dom('.leaflet-rain-pane .leaflet-tile').exists('emoji tiles');
    await click(button('mm'));
    assert.strictEqual(currentURL(), '/?dots=mm&rainy=1');
    assert.dom('.wt-legend-emoji').doesNotExist();
    assert.dom('.wt-legend-dots').includesText('60mm');
    assert.dom('.leaflet-rain-pane .leaflet-tile').doesNotExist();
  });

  test('dates over the night stops: months, weeks or none', async function (assert) {
    const dates = () =>
      findAll('.leaflet-labels-pane .wt-stop-date').map((d) =>
        d.textContent?.trim(),
      );
    const option = (text: string) =>
      findAll('[aria-label="Dates on the route"] button').find(
        (b) => b.textContent?.trim() === text,
      )!;
    await visit('/?start=2025-03-28');
    assert.deepEqual(
      dates(),
      [
        new Date(2025, 2, 28).toLocaleDateString(undefined, {
          day: 'numeric',
          month: 'short',
        }),
        new Date(2025, 3, 1).toLocaleDateString(undefined, {
          day: 'numeric',
          month: 'short',
        }),
        new Date(2025, 4, 1).toLocaleDateString(undefined, {
          day: 'numeric',
          month: 'short',
        }),
      ],
      'the start, and the first nights in April and May',
    );
    await click(option('Weeks'));
    assert.strictEqual(currentURL(), '/?dates=weeks&start=2025-03-28');
    assert.strictEqual(dates()[0], 'Week 1');
    assert.strictEqual(dates()[1], 'Week 2');
    await click(option('Off'));
    assert.deepEqual(dates(), []);
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
