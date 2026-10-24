import { module, test } from 'qunit';
import { render } from '@ember/test-helpers';
import { setupRenderingTest } from 'forkcast/tests/helpers';
import { not } from 'forkcast/utils/helpers';

module('Integration | Helper | not', function (hooks) {
  setupRenderingTest(hooks);

  test('it negates a value in a template', async function (assert) {
    await render(
      <template>
        <button type="button" disabled={{not true}}>a</button>
        <button type="button" disabled={{not 0}}>b</button>
      </template>,
    );
    assert.dom('button:first-child').isNotDisabled();
    assert.dom('button:last-child').isDisabled();
  });
});
