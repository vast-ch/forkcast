import { find, findAll } from '@ember/test-helpers';

/** The button (or button-like label) whose text is `text`. */
export function button(text: string): HTMLElement {
  const el = findAll('button, label.wt-btn').find(
    (b) => b.textContent?.trim() === text,
  );
  if (!el) throw new Error(`No button "${text}"`);
  return el as HTMLElement;
}

/** The form field labelled `text` (with `optional`, null when there's none). */
export function field(text: string): HTMLInputElement;
export function field(
  text: string,
  options: { optional: true },
): HTMLInputElement | null;
export function field(
  text: string,
  options?: { optional: true },
): HTMLInputElement | null {
  const label = findAll('label').find((l) => l.textContent?.trim() === text);
  const input =
    label && find(`#${CSS.escape(label.getAttribute('for') ?? '')}`);
  if (!input && !options?.optional) throw new Error(`No field "${text}"`);
  return (input as HTMLInputElement | null) ?? null;
}
