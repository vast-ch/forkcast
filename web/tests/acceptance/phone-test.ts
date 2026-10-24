import { module, test } from 'qunit';
import Service from '@ember/service';
import { click, find, visit } from '@ember/test-helpers';
import { setupApplicationTest } from 'forkcast/tests/helpers';
import { button } from 'forkcast/tests/helpers/find';

class PhoneMedia extends Service {
  isPhone = true;
}

module('Acceptance | phone', function (hooks) {
  setupApplicationTest(hooks);

  hooks.beforeEach(function () {
    this.owner.register('service:media', PhoneMedia);
  });

  test('settings and the trip summary live in the drawer', async function (assert) {
    await visit('/');
    assert.dom('.wt-phone').exists('the phone layout');
    assert.dom('.wt-summary').doesNotExist('no summary under the chart');

    await click(button('Settings'));
    assert
      .dom('[role="dialog"] .wt-summary')
      .exists('the summary is in the drawer');
    assert.dom('[role="dialog"] #h-trip').hasText('Trip');
  });

  test('drawing closes the drawer and shows its controls over the map', async function (assert) {
    await visit('/');
    await click(button('Settings'));
    await click(button('Draw a route'));
    assert.dom('[role="dialog"]').doesNotExist();
    assert.ok(find('.wt-phone-map [aria-label="Drawing a route"]'));
    await click(button('Cancel'));
    assert.dom('[aria-label="Drawing a route"]').doesNotExist();
  });
});
