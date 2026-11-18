import { module, test } from 'qunit';
import { click, currentURL, findAll, select, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
import { ROUTE_COLORS } from 'forkcast/services/planner';

/** The map's lines drawn in a colour. */
const lines = (color: string) =>
  findAll(`.leaflet-overlay-pane path[stroke="${color}"]`);

/** The day chart's column for day `n`. */
const column = (n: number) =>
  findAll('[role="slider"] g.cursor-pointer').find(
    (g) => g.querySelector('text')?.textContent?.trim() === String(n),
  )!;

/** The selected day on each route, as the chart's table has it: the route's
 * name and its climbing. */
const days = () =>
  findAll('.wt-compare tbody tr').map((tr) =>
    [...tr.querySelectorAll('td')]
      .slice(0, 2)
      .map((td) => td.textContent?.trim()),
  );

/** The purple of the selected day's stretch on the map. */
const PICK = '#a020f0';

module('Acceptance | compare routes', function (hooks) {
  setupApplicationTest(hooks);

  test('one route looks just like several: a row, a band, a column', async function (assert) {
    await visit('/?highlightedDay=3');
    assert.dom('.wt-ride').exists({ count: 1 });
    assert.dom('.wt-band').exists({ count: 1 }, 'its band, in its colour');
    assert.ok(lines(ROUTE_COLORS[0]!).length, 'the first colour, alone too');
    assert.dom('.wt-compare tbody tr').exists({ count: 1 }, "the day's table");
    assert
      .dom('.wt-summary thead th:not(:first-child)')
      .exists({ count: 1 }, 'a stats column');
    assert
      .dom('[aria-label="Remove Interlaken – Málaga"]')
      .isDisabled('the last route stays');
  });

  test('a route added goes into the URL, onto the map and into the chart', async function (assert) {
    await visit('/');
    await select('#add-route', 'ev15');
    assert.strictEqual(currentURL(), '/?routeIds=interlaken-malaga~ev15');
    assert.dom('.wt-ride').exists({ count: 2 });
    assert.dom('#route-2 option:checked').includesText('Rhine');
    assert.dom('#add-route').hasValue('', 'the add list goes back to empty');
    assert.dom('.wt-band').exists({ count: 2 }, 'a band per route');
    assert.ok(lines(ROUTE_COLORS[0]!).length, 'the first in its colour');
    assert.ok(lines(ROUTE_COLORS[1]!).length, 'the second in its own');
    assert
      .dom('.wt-summary thead th:not(:first-child)')
      .exists({ count: 2 }, 'the trips at a glance, a column each');
  });

  test('one selected day, on every route', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15');
    await click(column(3));
    assert.ok(currentURL().includes('highlightedDay=3'), currentURL());
    const rows = days();
    assert.strictEqual(rows.length, 2);
    assert.ok(rows[0]![0]!.includes('Interlaken'), rows[0]![0]);
    assert.ok(rows[1]![0]!.includes('Rhine'), rows[1]![0]);
    assert.ok(
      rows.every(([, climbing]) => climbing?.endsWith('m up')),
      'the climbing',
    );
    assert.strictEqual(lines(PICK).length, 2, "each route's stretch");
  });

  test('a shorter trip has arrived on later days', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev14');
    await click(column(31));
    assert.deepEqual(days()[1]?.[1], '🏁');
    assert.strictEqual(lines(PICK).length, 1, 'only the longer one rides on');
  });

  test('a route turns round, and only the first one clears the day', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15&highlightedDay=4');
    await click(
      '[aria-label="Ride EuroVelo 15 – Rhine Cycle Route the other way"]',
    );
    assert.ok(currentURL().includes('routeIds=interlaken-malaga~!ev15'));
    assert.ok(currentURL().includes('highlightedDay=4'), 'the day stays');
    await click('[aria-label="Ride Interlaken – Málaga the other way"]');
    assert.ok(currentURL().includes('routeIds=!interlaken-malaga~!ev15'));
    assert.notOk(currentURL().includes('highlightedDay'), 'the day goes');
  });

  test('a route is swapped in its own list, keeping its place', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15&highlightedDay=4');
    await select('#route-2', 'ev14');
    assert.ok(currentURL().includes('routeIds=interlaken-malaga~ev14'));
    assert.ok(currentURL().includes('highlightedDay=4'), 'the day stays');
    await select('#route-1', 'ev6');
    assert.strictEqual(currentURL(), '/?routeIds=ev6~ev14', 'the day goes');
  });

  test('the same route again comes the other way', async function (assert) {
    await visit('/?routeIds=ev6');
    await select('#add-route', 'ev6');
    assert.strictEqual(currentURL(), '/?routeIds=ev6~!ev6');
  });

  test('up to three routes, and each can go again', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15');
    await select('#add-route', 'ev14');
    assert.dom('#add-route').doesNotExist('no room for a fourth');
    assert.dom('.wt-band').exists({ count: 3 });
    await click('[aria-label="Remove EuroVelo 15 – Rhine Cycle Route"]');
    assert.strictEqual(currentURL(), '/?routeIds=interlaken-malaga~ev14');
    await click('[aria-label="Remove EuroVelo 14 – Waters of Central Europe"]');
    assert.strictEqual(currentURL(), '/', 'the default route alone');
    assert
      .dom('.wt-summary thead th:not(:first-child)')
      .exists({ count: 1 }, 'the stats have one column again');
  });

  test('a link keeps the routes it can, and a broken one reads as the default', async function (assert) {
    await visit('/?routeIds=ev15~nowhere~ev15~ev14~ev6');
    assert.dom('#route-1 option:checked').includesText('Rhine');
    assert.dom('.wt-ride').exists({ count: 3 }, 'unknown and twice go');
    await visit('/?routeIds=ev15,ev14');
    assert.dom('#route-1 option:checked').includesText('Interlaken');
    assert.dom('.wt-ride').exists({ count: 1 });
  });
});
