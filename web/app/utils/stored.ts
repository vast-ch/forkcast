import { TrackedObject } from 'tracked-built-ins';

// Values kept in this browser's localStorage, never sent anywhere (see the
// privacy rule in CLAUDE.md). A property marked `@stored` works like
// `@tracked` and also survives a reload:
//
//   @stored('map-view', parseView) view?: MapView;
//
// Each is one JSON value under `storage.prefix + key`. What's read back is
// checked by `parse`; anything it rejects (undefined) leaves the default.

export const storage = new TrackedObject({
  /** Prefix of every key; tests use their own (tests/helpers). */
  prefix: 'forkcast:',
  /** Set when the browser refused the last write (storage full or switched
   * off): it's kept for this visit only. */
  failed: false,
});

function read(key: string): unknown {
  try {
    const raw = localStorage.getItem(storage.prefix + key);
    return raw === null ? undefined : JSON.parse(raw);
  } catch {
    return undefined;
  }
}

function write(key: string, value: unknown): void {
  try {
    localStorage.setItem(storage.prefix + key, JSON.stringify(value));
    storage.failed = false;
  } catch {
    storage.failed = true;
  }
}

/** A property kept in localStorage under `key`; see the top of this file. */
export function stored<T>(key: string, parse: (raw: unknown) => T | undefined) {
  return function (
    _target: object,
    _name: string,
    desc?: { initializer?: () => T },
  ): void {
    const cells = new WeakMap<object, { value: T | undefined }>();
    const cell = (owner: object) => {
      let c = cells.get(owner);
      if (!c) {
        const value = parse(read(key)) ?? desc?.initializer?.call(owner);
        c = new TrackedObject({ value });
        cells.set(owner, c);
      }
      return c;
    };
    return {
      configurable: true,
      enumerable: true,
      get(this: object): T | undefined {
        return cell(this).value;
      },
      set(this: object, value: T) {
        cell(this).value = value;
        write(key, value);
      },
      // Legacy decorators replace the field with the descriptor returned;
      // TypeScript types them as returning nothing.
    } as unknown as void;
  };
}

/** Parsers for `stored`. */
export const isText = (raw: unknown): string | undefined =>
  typeof raw === 'string' ? raw : undefined;
