import { module, test } from 'qunit';
import { rainEmojiTier } from 'forkcast/utils/layers';

module('Unit | Utility | layers', function () {
  test('rainy days a week pick an emoji, none under one', function (assert) {
    assert.strictEqual(rainEmojiTier(0.9), undefined);
    assert.strictEqual(rainEmojiTier(1)?.label, '1–2');
    assert.strictEqual(rainEmojiTier(3.5)?.label, '2–4');
    assert.strictEqual(rainEmojiTier(6)?.label, '4+ days');
  });
});
