import { module, test } from 'qunit';
import {
  isPlaceShown,
  rainEmojiTier,
  rainEmojiTiers,
} from 'forkcast/utils/layers';

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

  test('zoomed in, the city setting picks the towns', function (assert) {
    assert.true(isPlaceShown('top10', 7, 60_000, 10, false));
    assert.false(isPlaceShown('top10', 7, 2_000_000, 11, false));
    assert.true(isPlaceShown('big', 7, 600_000, 30, false));
    assert.false(isPlaceShown('big', 7, 400_000, 1, false));
    assert.false(isPlaceShown('off', 7, 600_000, 1, true));
  });

  test('zoomed out, only the capitals', function (assert) {
    assert.false(isPlaceShown('top10', 5.5, 9_000_000, 2, false));
    assert.false(isPlaceShown('big', 5.5, 9_000_000, 2, false));
    assert.true(isPlaceShown('top10', 5.5, 9_000_000, 1, true));
    assert.false(isPlaceShown('off', 5.5, 9_000_000, 1, true));
    assert.true(isPlaceShown('top10', 6, 9_000_000, 2, false));
  });

  test('capitals show with every setting but off', function (assert) {
    // Bern: a capital of about 120,000, not the biggest Swiss town.
    assert.true(isPlaceShown('big', 7, 120_000, 5, true));
    assert.true(isPlaceShown('big', 5.5, 120_000, 5, true));
  });
});
