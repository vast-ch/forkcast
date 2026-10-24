import { module, test } from 'qunit';
import { render } from '@ember/test-helpers';
import { setupRenderingTest } from 'forkcast/tests/helpers';
import TempPill from 'forkcast/components/temp-pill';

module('Integration | Component | temp-pill', function (hooks) {
  setupRenderingTest(hooks);

  test('it shows the temperature in its colour from the scale', async function (assert) {
    await render(<template><TempPill @t={{24.4}} /></template>);
    assert.dom('.wt-temp-pill').hasText('24°C');
    assert.dom('.wt-temp-pill').hasAttribute('style', /background: (#|rgb)/);
  });

  test('it shows a dash where there is no climate data', async function (assert) {
    await render(<template><TempPill @t={{null}} /></template>);
    assert.dom('.wt-temp-pill').hasText('–');
    assert.dom('.wt-temp-pill').hasAttribute('style', /var\(--wt-band\)/);
  });
});
