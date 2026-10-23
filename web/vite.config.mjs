import tailwindcss from '@tailwindcss/vite';
import { defineConfig } from 'vite';
import { extensions, classicEmberSupport, ember } from '@embroider/vite';
import { babel } from '@rollup/plugin-babel';

const DEFAULT_APP_URL = 'http://127.0.0.1:4200';

// The dev container is served over OrbStack's HTTPS domain, so the HMR client
// must connect with wss on 443 rather than ws on Vite's own port.
function hmrClientConfig() {
  const appURL = new URL(process.env.APP_URL || DEFAULT_APP_URL);
  const protocol = appURL.protocol === 'https:' ? 'wss' : 'ws';
  const port = appURL.port || (appURL.protocol === 'https:' ? '443' : '80');
  return { clientPort: Number(port), protocol };
}

export default defineConfig({
  server: {
    host: '0.0.0.0',
    port: 4200,
    allowedHosts: ['ui.wheelther.orb.local'],
    hmr: hmrClientConfig(),
  },
  plugins: [
    classicEmberSupport(),
    ember(),
    babel({
      babelHelpers: 'runtime',
      extensions,
    }),
    tailwindcss(),
  ],
  optimizeDeps: {
    // See winds-mobi-client-web: Frontile's collections package breaks Vite's prebundling.
    exclude: ['ember-page-title', '@frontile/collections'],
  },
});
