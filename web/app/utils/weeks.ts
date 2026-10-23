// The map's time steps: each month split into four quarters (~ a week each).
// A quarter-month rather than a calendar week keeps the familiar month grid
// and lines up with the monthly data the seasonal curves are fitted to.

import { MONTHS } from './climate';

export interface WeekSlot {
  /** 0 … 47 */
  index: number;
  month: number;
  quarter: number;
  /** First and last day of the month it covers */
  from: number;
  to: number;
  /** e.g. "9–16 Jan" */
  label: string;
  /** Middle of the slot as a position in the year, 0 … 1 */
  phase: number;
}

const LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

export const WEEKS: WeekSlot[] = MONTHS.flatMap((name, month) => {
  const days = LENGTHS[month]!;
  return [0, 1, 2, 3].map((quarter) => {
    const from = Math.floor((quarter * days) / 4) + 1;
    const to = Math.floor(((quarter + 1) * days) / 4);
    return {
      index: month * 4 + quarter,
      month,
      quarter,
      from,
      to,
      label: `${from}–${to} ${name}`,
      phase: (month + (quarter + 0.5) / 4) / 12,
    };
  });
});

/** Index of the last slot (47). */
export const LAST_WEEK = WEEKS.length - 1;

/** The slot a date falls in. */
export function weekOfDate(date: Date): number {
  const month = date.getMonth();
  const days = LENGTHS[month]!;
  const quarter = Math.min(3, Math.floor(((date.getDate() - 1) * 4) / days));
  return month * 4 + quarter;
}
