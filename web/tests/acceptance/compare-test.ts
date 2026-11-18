import { module, test } from 'qunit';
import {
  click,
  currentURL,
  find,
  findAll,
  select,
  visit,
} from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
import { COMPARE_COLORS } from 'forkcast/services/planner';

/** The map's lines drawn in a colour. */
const lines = (color: string) =>
  findAll(`.leaflet-overlay-pane path[stroke="${color}"]`);

/** The day chart's column for day `n`. */
const column = (n: number) =>
  findAll('[role="slider"] g.cursor-pointer').find(
    (g) => g.querySelector('text')?.textContent?.trim() === String(n),
  )!;

/** The selected day on each route, as the chart's table has it. */
const compared = () =>
  findAll('.wt-compare tbody tr').map((tr) =>
    [...tr.querySelectorAll('td')]
      .slice(0, 2)
      .map((td) => td.textContent?.trim()),
  );

/** The purple of the selected day's stretch on the map. */
const PICK = '#a020f0';

module('Acceptance | compare routes', function (hooks) {
  setupApplicationTest(hooks);

  test('a route to compare goes into the URL, onto the map and into the chart', async function (assert) {
    await visit('/');
    assert.dom('.wt-band').doesNotExist('one route: no bands to tell apart');
    await select('#compare-picker', 'ev15');
    assert.strictEqual(currentURL(), '/?routeIds=interlaken-malaga~ev15');
    assert.dom('.wt-compared').exists({ count: 1 });
    assert.dom('.wt-compared').includesText('Rhine');
    assert.dom('.wt-band').exists({ count: 2 }, 'a band per route');
    assert.ok(lines(COMPARE_COLORS[0]!).length, 'the first in its colour');
    assert.ok(lines(COMPARE_COLORS[1]!).length, 'the second in its own');
    assert.dom('.wt-summary').doesNotExist();
    assert
      .dom('.wt-summary-compare thead th')
      .exists({ count: 2 }, 'the trips at a glance, a column each');
  });

  test('one selected day, on every route', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15');
    await click(column(3));
    assert.ok(currentURL().includes('highlightedDay=3'), currentURL());
    const rows = compared();
    assert.strictEqual(rows.length, 2);
    assert.ok(rows[0]![0]!.includes('Interlaken'), rows[0]![0]);
    assert.ok(rows[1]![0]!.includes('Rhine'), rows[1]![0]);
    assert.ok(
      rows.every(([, riding]) => riding?.endsWith('m up')),
      'riding',
    );
    assert.strictEqual(lines(PICK).length, 2, "each route's stretch");
  });

  test('a shorter trip ends with a flag and has arrived on later days', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev14');
    assert.dom('.wt-arrived').exists({ count: 1 });
    await click(column(31));
    assert.deepEqual(compared()[1]?.[1], 'Arrived');
    assert.strictEqual(lines(PICK).length, 1, 'only the longer one rides on');
  });

  test('a compared route turns round and keeps the day', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15&highlightedDay=4');
    await click(
      '[aria-label="Ride EuroVelo 15 – Rhine Cycle Route the other way"]',
    );
    assert.ok(currentURL().includes('routeIds=interlaken-malaga~!ev15'));
    assert.ok(currentURL().includes('highlightedDay=4'), 'the day stays');
    assert.dom('.wt-compared').includesText('(other way)');
  });

  test('the same route again comes the other way', async function (assert) {
    await visit('/?routeIds=ev6');
    await select('#compare-picker', 'ev6');
    assert.strictEqual(currentURL(), '/?routeIds=ev6~!ev6');
  });

  test('up to three routes, and each can go again', async function (assert) {
    await visit('/?routeIds=interlaken-malaga~ev15');
    await select('#compare-picker', 'ev14');
    assert.dom('#compare-picker').doesNotExist('no room for a fourth');
    assert.dom('.wt-band').exists({ count: 3 });
    await click(
      '[aria-label="Stop comparing EuroVelo 15 – Rhine Cycle Route"]',
    );
    assert.strictEqual(currentURL(), '/?routeIds=interlaken-malaga~ev14');
    await click(
      '[aria-label="Stop comparing EuroVelo 14 – Waters of Central Europe"]',
    );
    assert.strictEqual(currentURL(), '/', 'the default route alone');
    assert.dom('.wt-summary').exists();
  });

  test('a link keeps the routes it can, and a broken one reads as the default', async function (assert) {
    await visit('/?routeIds=ev15~nowhere~ev15~ev14~ev6');
    assert.dom('#route-picker option:checked').includesText('Rhine');
    assert.dom('.wt-compared').exists({ count: 2 }, 'unknown and twice go');
    await visit('/?routeIds=ev15,ev14');
    assert.dom('#route-picker option:checked').includesText('Interlaken');
    assert.notOk(find('.wt-compared'));
  });
});
