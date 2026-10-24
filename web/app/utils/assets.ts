// The data files built by the `data` container (data/out, mounted at /data-out).
// Importing them as assets gives every file a content-hashed URL in production
// builds, so they can be cached for a year without ever going stale.
//
// Every load is registered with Ember's test waiters, so tests settle once
// the data has arrived (no polling in tests).

import { waitForPromise } from '@ember/test-waiters';

const urls = import.meta.glob<string>('/data-out/**/*.{json,bin}', {
  query: '?url',
  import: 'default',
  eager: true,
});

/** Whether a data file exists (some continents lack optional ones). */
export function hasAsset(path: string): boolean {
  return `/data-out/${path}` in urls;
}

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

async function load(path: string): Promise<Response> {
  const res = await fetch(assetUrl(path));
  if (!res.ok) throw new Error(`Could not load ${path} (HTTP ${res.status}).`);
  return res;
}

export function fetchJson<T>(path: string): Promise<T> {
  return waitForPromise(load(path).then((r) => r.json() as Promise<T>));
}

export function fetchBuffer(path: string): Promise<ArrayBuffer> {
  return waitForPromise(load(path).then((r) => r.arrayBuffer()));
}
