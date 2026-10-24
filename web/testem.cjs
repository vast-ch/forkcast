'use strict';

// Chromium in the dev container (web/Dockerfile), Chrome elsewhere.
const browser = require('node:fs').existsSync('/usr/bin/chromium')
  ? 'Chromium'
  : 'Chrome';

if (typeof module !== 'undefined') {
  module.exports = {
    test_page: 'tests/index.html?hidepassed',
    cwd: 'dist-tests',
    disable_watching: true,
    launch_in_ci: [browser],
    launch_in_dev: [browser],
    browser_start_timeout: 120,
    browser_args: {
      [browser]: {
        ci: [
          // --no-sandbox is needed when running Chrome inside a container
          process.env.CI || process.env.CHROME_NO_SANDBOX
            ? '--no-sandbox'
            : null,
          '--headless',
          '--disable-dev-shm-usage',
          '--disable-software-rasterizer',
          '--mute-audio',
          '--remote-debugging-port=0',
          '--window-size=1440,900',
        ].filter(Boolean),
      },
    },
  };
}
