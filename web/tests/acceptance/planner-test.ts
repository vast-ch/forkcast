import { module, test } from 'qunit';
import { click, currentURL, fillIn, findAll, visit } from '@ember/test-helpers';
import { setupApplicationTest, storeAsApp } from 'forkcast/tests/helpers';
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
    assert.strictEqual(currentURL(), '/?kmPerDay=160');
    assert.true(Number(summary('Days')) < days, 'longer days, fewer of them');
  });

  test('settings in the URL are read back', async function (assert) {
    await visit('/?kmPerDay=160&restDays=0');
    assert.dom(field('km per day')).hasValue('160');
    assert.strictEqual(summary('Rest days'), '0');
  });

  test('map details switch their layers on and off', async function (assert) {
    await visit('/');
    assert.dom('.leaflet-relief-pane img').exists();
    await click(button('Relief'));
    assert.strictEqual(currentURL(), '/?relief=false');
    assert.dom('.leaflet-relief-pane img').doesNotExist();
    await click(button('Relief'));
    assert.strictEqual(currentURL(), '/');
    assert.dom('.leaflet-relief-pane img').exists();
  });

  test('city names: the 10 biggest per country, the big ones, or none', async function (assert) {
    const places = () => findAll('.leaflet-labels-pane .wt-place').length;
    // Zoomed in on the Alps, past where only capitals are named.
    storeAsApp('map-view', { lat: 46.5, lon: 8, zoom: 7 });
    await visit('/');
    const top10 = places();
    assert.ok(top10 > 0, 'the 10 biggest per country show at first');
    await click(button('500k+'));
    assert.strictEqual(currentURL(), '/?cities=big');
    assert.notStrictEqual(places(), top10, 'a different set of towns');
    assert.dom('.leaflet-labels-pane .wt-place').exists();
    const off = findAll('[aria-label="City names shown"] button').find(
      (b) => b.textContent?.trim() === 'Off',
    )!;
    await click(off);
    assert.strictEqual(currentURL(), '/?cities=off');
    assert.dom('.leaflet-labels-pane .wt-place').doesNotExist();
  });

  test('zoomed out on the continent, only the capitals are named', async function (assert) {
    storeAsApp('map-view', { lat: 50, lon: 10, zoom: 5 });
    await visit('/');
    const places = findAll('.leaflet-labels-pane .wt-place');
    assert.ok(places.length > 20, 'the capitals');
    assert.true(places.every((p) => p.classList.contains('is-capital')));
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
    assert.strictEqual(currentURL(), '/?rainMetric=mm&rainThreshold=1');
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
    const month = (m: number) =>
      new Date(2025, m, 1).toLocaleDateString(undefined, { month: 'short' });
    await visit('/?start=2025-03-28');
    assert.deepEqual(
      dates(),
      [month(3), month(4)],
      'where the rider is on 1 April and 1 May; no mark for March',
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

  test('the start picker colours each day by the weather at the start', async function (assert) {
    /** The temperature a day of the open calendar shows, from its title. */
    const tempOn = (day: number) => {
      const cell = findAll('.wt-temp-day.has-temp').find(
        (d) =>
          d.textContent?.trim() === String(day) &&
          !d.classList.contains('is-outside'),
      );
      return Number(/(-?\d+)°C/.exec(cell?.getAttribute('title') ?? '')?.[1]);
    };

    await visit('/?start=2026-01-15');
    await click('#start-date');
    assert.ok(tempOn(15) < 10, 'a cold day in January at Interlaken');
    assert
      .dom('.wt-temp-day.has-temp')
      .hasAttribute('style', /background: rgb/);

    await click(`[data-key="2026-01-20"]`);
    assert.true(currentURL().includes('start=2026-01-20'), 'the day is picked');

    await visit('/?start=2026-07-15');
    await click('#start-date');
    assert.ok(tempOn(15) > 18, 'a warm one in July');
  });
});
