import { module, test } from 'qunit';
import { click, currentURL, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
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

  test('old section names still open the right tab', async function (assert) {
    await visit('/help/maths');
    assert.dom('[aria-current="page"]').hasText('Data');
    await visit('/help/privacy');
    assert.dom('[aria-current="page"]').hasText('Sharing & privacy');
  });

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
});
