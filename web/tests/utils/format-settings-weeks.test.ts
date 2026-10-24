import { describe, expect, it } from 'vitest';
import {
  fmtDaylight,
  fmtHours,
  fmtKm,
  fmtMm,
  fmtTemp,
} from 'forkcast/utils/format';
import { inLimits, isIsoDate, isoDate } from 'forkcast/utils/settings';
import { WEEKS, weekOfDate } from 'forkcast/utils/weeks';

describe('format', () => {
  it('writes units next to the numbers', () => {
    expect(fmtTemp(14.6)).toBe('15°C');
    expect(fmtTemp(Number.NaN)).toBe('–');
    expect(fmtMm(4.94)).toBe('4.9mm');
    expect(fmtMm(23.4)).toBe('23mm');
    expect(fmtKm(80)).toBe('80.0km');
    expect(fmtKm(2369.4)).toBe(`${(2369).toLocaleString()}km`);
    expect(fmtHours(3.81)).toBe('3h 49min');
  });

  it('names the polar extremes of daylight', () => {
    expect(fmtDaylight(24)).toBe('24h (midnight sun)');
    expect(fmtDaylight(0)).toBe('None (polar night)');
    expect(fmtDaylight(10.4)).toBe('10h 24min');
  });
});

describe('settings', () => {
  it('keeps the trip numbers in range', () => {
    expect(inLimits('km', 80)).toBe(true);
    expect(inLimits('km', 1000)).toBe(false);
    expect(inLimits('ride', 2.5)).toBe(false);
    expect(inLimits('speed', 21.5)).toBe(true);
    expect(inLimits('rest', 0)).toBe(true);
  });

  it('reads and writes dates as yyyy-mm-dd', () => {
    expect(isIsoDate('2026-10-24')).toBe(true);
    expect(isIsoDate('24.10.2026')).toBe(false);
    expect(isoDate(new Date(2026, 0, 5))).toBe('2026-01-05');
  });
});

describe('weeks', () => {
  it('splits the year into 48 quarter-months of 7 or 8 days', () => {
    expect(WEEKS).toHaveLength(48);
    expect(WEEKS.every((w) => w.days === 7 || w.days === 8)).toBe(true);
    expect(WEEKS[0]!.label).toBe('1–7 Jan');
  });

  it('finds the quarter-month of a date', () => {
    expect(weekOfDate(new Date(2026, 0, 1))).toBe(0);
    expect(weekOfDate(new Date(2026, 0, 31))).toBe(3);
    expect(weekOfDate(new Date(2026, 11, 31))).toBe(47);
  });
});
