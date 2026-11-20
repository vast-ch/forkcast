import tailwindcss from '@tailwindcss/vite';
import { defineConfig, searchForWorkspaceRoot } from 'vite';
import { extensions, classicEmberSupport, ember } from '@embroider/vite';
import { babel } from '@rollup/plugin-babel';
import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const DEFAULT_APP_URL = 'http://127.0.0.1:4200';

// The dev container is served over OrbStack's HTTPS domain, so the HMR client
// must connect with wss on 443 rather than ws on Vite's own port.
function hmrClientConfig() {
  const appURL = new URL(process.env.APP_URL || DEFAULT_APP_URL);
  const protocol = appURL.protocol === 'https:' ? 'wss' : 'ws';
  const port = appURL.port || (appURL.protocol === 'https:' ? '443' : '80');
  return { clientPort: Number(port), protocol };
}

// The app's own pages besides `/` (see app/router.ts): the help page, one
// per help section (app/help-sections.json) and the changelog. A static host serves
// `help/index.html` for /help and `help/<id>/index.html` for /help/<id>, so
// deep links work without a rewrite rule; 404.html is the fallback page hosts
// such as GitHub Pages and Netlify use.
const PAGES = [
  'help',
  'changelog',
  ...JSON.parse(readFileSync('app/help-sections.json', 'utf8')).map(
    (s) => `help/${s.id}`,
  ),
];

// The changelog page imports `/CHANGELOG.md`: a copy in web/ when building
// (netlify.toml, the Dockerfile), the repository's own in the dev container,
// where the repository is mounted read-only at /repo (compose.yaml).
const REPO_CHANGELOG = '/repo/CHANGELOG.md';
const devChangelog = existsSync(REPO_CHANGELOG);

function staticPages() {
  let outDir = 'dist';
  return {
    name: 'forkcast-static-pages',
    apply: 'build',
    configResolved(config) {
      outDir = config.build.outDir;
    },
    writeBundle() {
      const index = join(outDir, 'index.html');
      for (const page of PAGES) {
        mkdirSync(join(outDir, page), { recursive: true });
        copyFileSync(index, join(outDir, page, 'index.html'));
      }
      copyFileSync(index, join(outDir, '404.html'));
    },
  };
}

export default defineConfig({
  server: {
    host: '0.0.0.0',
    port: 4200,
    allowedHosts: ['ui.forkcast.orb.local'],
    hmr: hmrClientConfig(),
    fs: {
      allow: [
        searchForWorkspaceRoot(process.cwd()),
        ...(devChangelog ? [REPO_CHANGELOG] : []),
      ],
    },
  },
  resolve: {
    alias: devChangelog
      ? [{ find: /^\/CHANGELOG\.md(?=\?|$)/, replacement: REPO_CHANGELOG }]
      : [],
  },
  plugins: [
    classicEmberSupport(),
    ember(),
    babel({
      babelHelpers: 'runtime',
      extensions,
    }),
    tailwindcss(),
    staticPages(),
  ],
  build: {
    // Data files stay files, even small ones, rather than data: URLs inlined
    // into the code: the content security policy only lets the app fetch from
    // its own origin (see security-headers.conf).
    assetsInlineLimit: (file) =>
      /\.(json|bin)(\?|$)/.test(file) ? false : undefined,
  },
  optimizeDeps: {
    // See winds-mobi-client-web: Frontile's collections package breaks Vite's prebundling.
    exclude: ['ember-page-title', '@frontile/collections'],
  },
});
