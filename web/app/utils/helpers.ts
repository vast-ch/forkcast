/** Template helper: the opposite of a value, e.g. `disabled={{not ok}}`. */
export const not = (v: unknown): boolean => !v;

/** No number to show: absent, or NaN (no climate data there). */
export const isMissing = (
  n: number | null | undefined,
): n is null | undefined => n === null || n === undefined || Number.isNaN(n);

/** A caught error's message, for showing to the user. */
export const errorMessage = (e: unknown): string =>
  e instanceof Error ? e.message : String(e);
