import {
  setupApplicationTest as upstreamSetupApplicationTest,
  setupRenderingTest as upstreamSetupRenderingTest,
  setupTest as upstreamSetupTest,
  type SetupTestOptions,
} from 'ember-qunit';
import MyRoutesService from 'forkcast/services/my-routes';

/** Tests keep their routes under their own key, never touching yours, and
 * start each test with none. */
export const TEST_ROUTES_KEY = 'forkcast:test-routes';
class TestRoutes extends MyRoutesService {
  get storageKey() {
    return TEST_ROUTES_KEY;
  }
}
function isolateRoutes(hooks: NestedHooks) {
  hooks.beforeEach(function () {
    localStorage.removeItem(TEST_ROUTES_KEY);
    this.owner.register('service:my-routes', TestRoutes);
  });
}

// This file exists to provide wrappers around ember-qunit's
// test setup functions. This way, you can easily extend the setup that is
// needed per test type.

function setupApplicationTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupApplicationTest(hooks, options);
  isolateRoutes(hooks);

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
  isolateRoutes(hooks);

  // Additional setup for rendering tests can be done here.
}

function setupTest(hooks: NestedHooks, options?: SetupTestOptions) {
  upstreamSetupTest(hooks, options);
  isolateRoutes(hooks);

  // Additional setup for unit tests can be done here.
}

export { setupApplicationTest, setupRenderingTest, setupTest };
