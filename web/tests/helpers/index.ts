import {
  setupApplicationTest as upstreamSetupApplicationTest,
  setupRenderingTest as upstreamSetupRenderingTest,
  setupTest as upstreamSetupTest,
  type SetupTestOptions,
} from 'ember-qunit';
import { storage } from 'forkcast/utils/stored';

/** Tests keep what the app stores in the browser under their own keys,
 * never touching yours, and start each test with nothing stored. */
storage.prefix = 'forkcast:test:';
function isolateStorage(hooks: NestedHooks) {
  hooks.beforeEach(function () {
    for (const key of Object.keys(localStorage)) {
      if (key.startsWith(storage.prefix)) localStorage.removeItem(key);
    }
    storage.failed = false;
  });
}

/** Store `value` under `key` as the app would, e.g. as left by an earlier
 * visit. */
export function storeAsApp(key: string, value: unknown): void {
  localStorage.setItem(storage.prefix + key, JSON.stringify(value));
}

/** What the app stored under `key`. */
export function storedByApp(key: string): unknown {
  const raw = localStorage.getItem(storage.prefix + key);
  return raw === null ? undefined : JSON.parse(raw);
}

// This file exists to provide wrappers around ember-qunit's
// test setup functions. This way, you can easily extend the setup that is
// needed per test type.

function setupApplicationTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupApplicationTest(hooks, options);
  isolateStorage(hooks);

  // Additional setup for application tests can be done here.
  //
  // For example, if you need an authenticated session for each
  // application test, you could do:
  //
  // hooks.beforeEach(async function () {
  //   await authenticateSession(); // ember-simple-auth
  // });
  //
  // This is also a good place to call test setup functions coming
  // from other addons:
  //
  // setupIntl(hooks, 'en-us'); // ember-intl
  // setupMirage(hooks); // ember-cli-mirage
}

function setupRenderingTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupRenderingTest(hooks, options);
  isolateStorage(hooks);

  // Additional setup for rendering tests can be done here.
}

function setupTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupTest(hooks, options);
  isolateStorage(hooks);

  // Additional setup for unit tests can be done here.
}

export { setupApplicationTest, setupRenderingTest, setupTest };
