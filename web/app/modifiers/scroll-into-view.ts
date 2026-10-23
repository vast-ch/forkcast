import { modifier } from 'ember-modifier';

/** Scrolls the element to the middle of its scrolling parent whenever `when` becomes true. */
const scrollIntoView = modifier<{
  Element: HTMLElement;
  Args: { Positional: [boolean] };
}>((element, [when]) => {
  if (!when) return;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  element.scrollIntoView({
    inline: 'center',
    block: 'nearest',
    behavior: reduce ? 'auto' : 'smooth',
  });
});

export default scrollIntoView;
