import { module, test } from 'qunit';
import { rainEmojiTier, rainEmojiTiers } from 'forkcast/utils/layers';

module('Unit | Utility | layers', function () {
  test('rainy days a week pick an emoji, none under one', function (assert) {
    assert.strictEqual(rainEmojiTier(0.9, 5), undefined);
    assert.strictEqual(rainEmojiTier(1, 5)?.label, '1–1½');
    assert.strictEqual(rainEmojiTier(1.7, 5)?.label, '1½–2');
    assert.strictEqual(rainEmojiTier(4, 5)?.label, '2+ days');
  });

  test('each rainy-day threshold has steps its rain reaches', function (assert) {
    const labels = (mm: number) => rainEmojiTiers(mm).map((t) => t.label);
    assert.deepEqual(labels(1), ['1–2', '2–3', '3+ days']);
    assert.deepEqual(labels(5), ['1–1½', '1½–2', '2+ days']);
    assert.deepEqual(labels(10), ['1–1½', '1½+ days']);
    assert.strictEqual(rainEmojiTier(0.9, 1), undefined, 'under 1 never shows');
  });
});
