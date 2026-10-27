import { module, test } from 'qunit';
import { click, currentURL, find, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
import { button } from 'forkcast/tests/helpers/find';
import sections from 'forkcast/help-sections.json';

module('Acceptance | help', function (hooks) {
  setupApplicationTest(hooks);

  test('/help opens the first tab', async function (assert) {
    await visit('/help');
    assert.dom('[aria-current="page"]').hasText(sections[0]!.label);
  });

  for (const s of sections) {
    test(`/help/${s.id} opens its tab`, async function (assert) {
      await visit(`/help/${s.id}`);
      assert.strictEqual(currentURL(), `/help/${s.id}`);
      assert.dom('[aria-current="page"]').hasText(s.label);
      assert.true(document.title.startsWith(s.label), document.title);
    });
  }

  test('tabs switch sections and the map link goes back', async function (assert) {
    await visit('/help');
    await click('a[href="/help/sources"]');
    assert.strictEqual(currentURL(), '/help/sources');
    await click('a.wt-help-link');
    assert.strictEqual(currentURL(), '/');
  });

  test('an unknown address opens the planner', async function (assert) {
    await visit('/europe');
    assert.dom('#route-picker').exists();
  });

  test('the start date demo colours its days for each town', async function (assert) {
    /** The selected day's temperature, from its tooltip. */
    const picked = () => {
      const title = find('[data-selected="true"] .wt-temp-day')?.getAttribute(
        'title',
      );
      return Number(/(-?\d+)°C/.exec(title ?? '')?.[1]);
    };

    // Straight to the help: the demo loads the climate itself.
    await visit('/help/trip');
    assert.dom('.wt-help-demo .wt-temp-day.has-temp').exists();
    await click(button('Nordkapp'));
    const north = picked();
    await click(button('Málaga'));
    assert.true(picked() > north, 'Málaga is warmer than Nordkapp');
    await click(button('Night low'));
    assert
      .dom('[data-selected="true"] .wt-temp-day')
      .hasAttribute('title', /^Low in Málaga: /);
  });

  test('the About tab links to the code, the maker and Discord', async function (assert) {
    await visit('/help/about');
    assert
      .dom('a[href="https://github.com/vast-ch/forkcast/issues/new"]')
      .exists();
    assert.dom('a[href="https://vast.ch/earth/"]').exists();
    assert.dom('img.wt-help-qr').hasAttribute('src', '/discord-qr.svg');
    await click('#about a[href="/help/sharing"]');
    assert.strictEqual(currentURL(), '/help/sharing');
  });
});
