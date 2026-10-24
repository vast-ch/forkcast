import { module, test } from 'qunit';
import { fillIn, render } from '@ember/test-helpers';
import { setupRenderingTest } from 'forkcast/tests/helpers';
import RangeInput from 'forkcast/components/range-input';

module('Integration | Component | range-input', function (hooks) {
  setupRenderingTest(hooks);

  test('it is a labelled slider that reports its value', async function (assert) {
    const seen: string[] = [];
    const onInput = (v: string) => seen.push(v);
    await render(
      <template>
        <RangeInput
          @label="Week"
          @value="3"
          @onInput={{onInput}}
          min="0"
          max="10"
        />
      </template>,
    );
    assert.dom('input[type="range"]').hasValue('3');
    assert.dom('label').hasText('Week');
    await fillIn('input[type="range"]', '7');
    assert.deepEqual(seen, ['7']);
  });
});
