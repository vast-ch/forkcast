// Distances on the Earth, for the route and the cycle network.

const RAD = Math.PI / 180;
/** Mean Earth radius, km */
const R = 6371.0088;

/** Great-circle distance in km (haversine). */
export function km(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number,
): number {
  const dLat = (lat2 - lat1) * RAD;
  const dLon = (lon2 - lon1) * RAD;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * RAD) * Math.cos(lat2 * RAD) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function haversineKm(
  a: { lat: number; lon: number },
  b: { lat: number; lon: number },
): number {
  return km(a.lat, a.lon, b.lat, b.lon);
}

/** Length of a line in km. */
export function lineKm(line: { lat: number; lon: number }[]): number {
  let total = 0;
  for (let i = 1; i < line.length; i++)
    total += haversineKm(line[i - 1]!, line[i]!);
  return total;
}
