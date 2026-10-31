import type { TOC } from '@ember/component/template-only';

/** The About tab in Nerd mode: how Forkcast is built and how to check it yourself. */
const NerdAbout: TOC<object> = <template>
  <section id="about">
    <h2>About Forkcast</h2>
    <p>
      Forkcast is open source:
      <a
        href="https://github.com/vast-ch/forkcast"
        target="_blank"
        rel="noopener noreferrer"
      >github.com/vast-ch/forkcast</a>. Issues and ideas go there too.
    </p>

    <h3>How it's built</h3>
    <dl class="wt-help-defs">
      <div><dt>The app</dt><dd>Ember with Vite and Embroider, TypeScript in .gts
          files, Leaflet for the map, Tailwind and Frontile for the interface.
          It runs entirely in the browser; Netlify serves the built files.</dd></div>
      <div><dt>The data</dt><dd>A Python pipeline (xarray, numpy) that downloads
          the sources once, then builds every file the app loads, offline. Each
          step rebuilds only when its inputs or its code changed.</dd></div>
      <div><dt>The tests</dt><dd>The app's own (unit, rendering and whole
          screens on the real data) and the pipeline's, on every change. The
          pipeline also refuses to publish climates that contradict known El
          Niño and La Niña effects.</dd></div>
    </dl>

    <h3>Measured, not claimed</h3>
    <p>
      Every precision statement in Nerd mode comes from the pipeline's verify
      step: our numbers against real days and years. Each run is kept with the
      code that measured it, so a change to how the numbers are made can be
      checked against the last: better, worse, or within noise.
    </p>
  </section>
</template>;

export default NerdAbout;
