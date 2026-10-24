/** Assert that a number is `expected` to `digits` decimal places. */
export function closeTo(
  assert: Assert,
  actual: number,
  expected: number,
  digits = 2,
  message = `${actual} ≈ ${expected}`,
): void {
  assert.pushResult({
    result: Math.abs(actual - expected) < 10 ** -digits / 2,
    actual,
    expected,
    message,
  });
}
