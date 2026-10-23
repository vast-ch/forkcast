// The data files built by the `data` container (data/out, mounted at /data-out).
// Importing them as assets gives every file a content-hashed URL in production
// builds, so they can be cached for a year without ever going stale.

const urls = import.meta.glob<string>('/data-out/**/*.{json,bin}', {
  query: '?url',
  import: 'default',
  eager: true,
});

/** URL of a data file, by its path inside data/out (e.g. "europe/climate.bin"). */
export function assetUrl(path: string): string {
  const url = urls[`/data-out/${path}`];
  if (!url) {
    throw new Error(
      `Missing data file ${path}. Build it with: docker compose --profile tools run --rm data`,
    );
  }
  return url;
}

export async function fetchJson<T>(path: string): Promise<T> {
  const res = await fetch(assetUrl(path));
  if (!res.ok) throw new Error(`Could not load ${path} (HTTP ${res.status}).`);
  return (await res.json()) as T;
}

export async function fetchBuffer(path: string): Promise<ArrayBuffer> {
  const res = await fetch(assetUrl(path));
  if (!res.ok) throw new Error(`Could not load ${path} (HTTP ${res.status}).`);
  return res.arrayBuffer();
}
