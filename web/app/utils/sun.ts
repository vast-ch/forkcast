// Sunrise and sunset from the sun's position (the "sunrise equation", as in
// NOAA's solar calculator; within a minute or two of published tables).
// Times are absolute (Julian days), so subtracting a sunrise in one place from
// a sunset in another needs no time zones.

const RAD = Math.PI / 180;
const J2000 = 2451545;
/** The sun's apparent upper edge at the horizon, with refraction. */
const HORIZON = -0.833 * RAD;
const TILT = 23.4397 * RAD;

type SunDay =
  | { kind: 'normal'; rise: number; set: number }
  | { kind: 'midnight-sun' }
  | { kind: 'polar-night' };

/** Sunrise and sunset (Julian days) at a place on a date, or why there are none. */
function sunDay(date: Date, lat: number, lon: number): SunDay {
  const julian = date.getTime() / 86400000 + 2440587.5;
  const n = Math.ceil(julian - J2000 + 0.0008);
  const meanNoon = n - lon / 360;
  const m = (357.5291 + 0.98560028 * meanNoon) % 360;
  const centre =
    1.9148 * Math.sin(m * RAD) +
    0.02 * Math.sin(2 * m * RAD) +
    0.0003 * Math.sin(3 * m * RAD);
  const longitude = ((m + centre + 180 + 102.9372) % 360) * RAD;
  const transit =
    J2000 +
    meanNoon +
    0.0053 * Math.sin(m * RAD) -
    0.0069 * Math.sin(2 * longitude);
  const declination = Math.asin(Math.sin(longitude) * Math.sin(TILT));
  const cosHour =
    (Math.sin(HORIZON) - Math.sin(lat * RAD) * Math.sin(declination)) /
    (Math.cos(lat * RAD) * Math.cos(declination));
  if (cosHour < -1) return { kind: 'midnight-sun' };
  if (cosHour > 1) return { kind: 'polar-night' };
  const half = Math.acos(cosHour) / RAD / 360;
  return { kind: 'normal', rise: transit - half, set: transit + half };
}

/**
 * Hours of daylight for a day that starts at `from` (its sunrise) and ends at
 * `to` (its sunset): 24 under the midnight sun, 0 in the polar night.
 */
export function daylightHours(
  date: Date,
  from: { lat: number; lon: number },
  to: { lat: number; lon: number },
): number {
  const a = sunDay(date, from.lat, from.lon);
  const b = sunDay(date, to.lat, to.lon);
  if (a.kind === 'normal' && b.kind === 'normal') {
    return Math.min(24, Math.max(0, (b.set - a.rise) * 24));
  }
  if (a.kind === 'midnight-sun' || b.kind === 'midnight-sun') return 24;
  return 0;
}
