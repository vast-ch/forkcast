// Tailwind class lists that several templates share, so a pattern is written
// once without a stylesheet: `class={{btn}}`, or `class="{{btn}} w-full"`.
// Colours and fonts are the tokens in app.css (`text-wt-muted`, `font-data`).

/** Keyboard focus on our own controls. */
export const focusRing =
  'focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-wt-accent';

// Each kind of button sets its own colours: of two utilities for the same
// property, the stylesheet's order wins, not the class list's, so a kind
// can't override another's.
const button =
  'inline-flex h-8 cursor-pointer items-center rounded-lg border px-3 text-sm font-medium focus-within:outline-2 focus-within:outline-wt-accent disabled:cursor-not-allowed disabled:opacity-45';
/** A plain action button (Frontile's Button rendered oversized here and its
 * press handling didn't respond to plain clicks). */
export const btn = `${button} border-wt-line bg-white text-wt-ink hover:bg-wt-accent-soft`;
/** The one action that matters most where it is: Save, Settings. */
export const btnPrimary = `${button} border-wt-ink bg-wt-ink text-white hover:bg-wt-accent`;
/** A button that doesn't compete with its neighbours: Cancel. */
export const btnGhost = `${button} border-transparent text-wt-ink hover:bg-wt-accent-soft`;

/** A floating panel over the map: the hover card, the legend. */
export const card =
  'rounded-md border border-wt-line bg-wt-paper/94 shadow-wt-card backdrop-blur-[4px]';

export const title = 'font-display text-base font-bold text-balance';

/** A small label in capitals over a value or a readout. */
export const eyebrow =
  'text-[0.7rem] tracking-[0.06em] text-wt-muted uppercase tabular-nums';

/** A row of label/value pairs (`<dl>` of `<div><dt><dd>`): the chart's
 * selected day, the help's demos. */
export const inlineStats =
  'flex flex-wrap gap-x-[0.9rem] gap-y-[0.2rem] text-[0.8rem] *:flex *:items-baseline *:gap-[0.3rem] [&_dd]:font-data [&_dd]:font-medium [&_dt]:text-wt-muted';

/** Help and changelog: one readable column, styled by element because the
 * changelog is rendered Markdown. */
export const helpColumn = 'mx-auto max-w-176';
export const prose = `${helpColumn} [&_a]:text-wt-accent [&_a]:underline [&_a]:underline-offset-2 [&_h2]:font-display [&_h2]:text-[1.35rem] [&_h2]:font-bold [&_h2]:tracking-[-0.01em] [&_h3]:mt-7 [&_h3]:font-display [&_h3]:text-[1.05rem] [&_h3]:font-bold [&_li]:max-w-[65ch] [&_li]:leading-[1.6] [&_p]:mt-3 [&_p]:max-w-[65ch] [&_p]:leading-[1.6] [&_section]:scroll-mt-4 [&_section]:pt-8 [&_ol]:mt-3 [&_ol]:flex [&_ol]:list-decimal [&_ol]:flex-col [&_ol]:gap-[0.35rem] [&_ol]:pl-[1.2rem] [&_ul]:mt-3 [&_ul]:flex [&_ul]:list-disc [&_ul]:flex-col [&_ul]:gap-[0.35rem] [&_ul]:pl-[1.2rem]`;
export const helpLink =
  'text-[0.85rem] font-medium text-wt-accent underline underline-offset-3 hover:text-wt-ink';
/** A live piece of the app inside the help, in a card. */
export const helpDemo =
  'mt-[0.9rem] rounded-lg border border-wt-line bg-white px-4 py-[0.9rem]';
/** The help's term/definition cards (`<dl>` of `<div><dt><dd>`). */
export const helpDefs =
  'mt-3 grid gap-2 *:grid *:grid-cols-[7rem_minmax(0,1fr)] *:gap-4 *:rounded-md *:border *:border-wt-line *:bg-white *:px-3 *:py-[0.6rem] max-[480px]:*:grid-cols-[minmax(0,1fr)] max-[480px]:*:gap-1 [&_dt]:font-data [&_dt]:font-medium';
/** Nerd mode's tables of measurements; scrolled sideways on narrow screens. A
 * cell's `.wt-help-verdict` is coloured by the cell's `data-verdict`. */
export const helpTable =
  'mt-4 mb-6 w-full border-collapse text-sm tabular-nums max-sm:block max-sm:overflow-x-auto [&_caption]:pb-[0.4rem] [&_caption]:text-left [&_caption]:text-wt-muted [&_small]:block [&_small]:text-wt-muted [&_td]:border-b [&_td]:border-wt-border [&_td]:px-2 [&_td]:py-[0.35rem] [&_td]:text-left [&_td]:align-top [&_th]:border-b [&_th]:border-wt-border [&_th]:px-2 [&_th]:py-[0.35rem] [&_th]:text-left [&_th]:align-top [&_[data-verdict=better]_.wt-help-verdict]:text-[#15803d] [&_[data-verdict=worse]_.wt-help-verdict]:text-[#c2410c]';
/** A note under the measurements: when they were made, or that they're missing. */
export const helpNote = 'text-[0.8rem] text-wt-muted';
