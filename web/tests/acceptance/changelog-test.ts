import { module, test } from 'qunit';
import { click, currentURL, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';

module('Acceptance | changelog', function (hooks) {
  setupApplicationTest(hooks);

  test('the help page links to the changelog, rendered from Markdown', async function (assert) {
    await visit('/help');
    await click('a[href="/changelog"]');

    assert.strictEqual(currentURL(), '/changelog');
    assert.dom('.wt-changelog h2').exists('a heading per release');
    assert.dom('.wt-changelog h2').doesNotIncludeText('#');
    assert.dom('.wt-changelog li').exists('the entries are lists');
    assert.dom('.wt-changelog h1').doesNotExist('the page has its own heading');
  });
});
