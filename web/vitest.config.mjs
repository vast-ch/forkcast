import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

// Unit tests for the app's plain TypeScript (app/utils): no browser, no Ember
// build, so they run in about a second. Components and routes would need the
// Ember test runner (tests/index.html) and a browser.
export default defineConfig({
  resolve: {
    alias: {
      forkcast: fileURLToPath(new URL('./app', import.meta.url)),
      // format.ts marks inline styles safe for Ember; outside Ember a string will do.
      '@ember/template': fileURLToPath(
        new URL('./tests/utils/ember-template-stub.ts', import.meta.url),
      ),
    },
  },
  test: {
    include: ['tests/utils/**/*.test.ts'],
    environment: 'node',
  },
});
