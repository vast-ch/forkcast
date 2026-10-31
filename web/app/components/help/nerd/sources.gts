import type { TOC } from '@ember/component/template-only';

/** The Sources tab in Nerd mode: full citations, with version, resolution and period. */
const NerdSources: TOC<{ Args: { years: string } }> = <template>
  <section id="sources">
    <h2>Sources and licences</h2>
    <table class="wt-help-table">
      <thead><tr><th scope="col">Dataset</th><th scope="col">Used for</th><th
            scope="col"
          >Resolution, period</th><th scope="col">Licence</th></tr></thead>
      <tbody>
        <tr><th scope="row"><a
              href="https://cds.climate.copernicus.eu/datasets/reanalysis-era5-land"
              target="_blank"
              rel="noopener noreferrer"
            >ERA5-Land</a>, C3S / ECMWF (Muñoz-Sabater et al. 2021, Earth Syst.
            Sci. Data 13: 4349–4383)</th>
          <td>Rain, the shape of highs and lows, terrain height; the variants'
            years</td>
          <td>0.1°, regridded to 0.25° by the CDS; daily rain, monthly means by
            hour of day;
            {{@years}}, and 1981–2025 for the variants</td>
          <td>Copernicus licence: contains modified Copernicus Climate Change
            Service information 2026</td></tr>
        <tr><th scope="row"><a
              href="https://crudata.uea.ac.uk/cru/data/hrg/"
              target="_blank"
              rel="noopener noreferrer"
            >CRU TS 4.10</a>, Climatic Research Unit, University of East Anglia
            (Harris et al. 2020, Sci. Data 7: 109)</th>
          <td>The level of highs and lows</td>
          <td>0.5°, monthly;
            {{@years}}</td>
          <td>Open Government Licence</td></tr>
        <tr><th scope="row"><a
              href="https://psl.noaa.gov/data/gridded/data.cpc.globaltemp.html"
              target="_blank"
              rel="noopener noreferrer"
            >CPC Global Unified Temperature</a>, NOAA PSL, Boulder, Colorado</th>
          <td>How far single days stray; the tests against real days</td>
          <td>0.5°, daily; 2011–2025</td>
          <td>Public domain</td></tr>
        <tr><th scope="row"><a
              href="https://www.cpc.ncep.noaa.gov/products/analysis_monitoring/ensostuff/ONI_v5.php"
              target="_blank"
              rel="noopener noreferrer"
            >Oceanic Niño Index</a>, NOAA CPC</th>
          <td>Which months were El Niño or La Niña</td>
          <td>Three-month seasons; 1981–2025</td>
          <td>Public domain</td></tr>
        <tr><th scope="row">Lapse rates (Rolland 2003, J. Climate 16: 1032–1046)</th>
          <td>The altitude correction</td>
          <td>Monthly, measured across the Alps</td>
          <td>Published values</td></tr>
        <tr><th scope="row"><a
              href="https://www.eurovelo.com"
              target="_blank"
              rel="noopener noreferrer"
            >EuroVelo GPX tracks</a>, European Cyclists' Federation</th>
          <td>The EuroVelo routes</td>
          <td>Downloaded 2026-10-23</td>
          <td>ODbL; EuroVelo® is a registered trademark of the ECF</td></tr>
        <tr><th scope="row"><a
              href="https://www.openstreetmap.org/copyright"
              target="_blank"
              rel="noopener noreferrer"
            >OpenStreetMap</a>
            contributors, via
            <a
              href="https://brouter.de"
              target="_blank"
              rel="noopener noreferrer"
            >BRouter</a>
            and the
            <a
              href="https://overpass-api.de"
              target="_blank"
              rel="noopener noreferrer"
            >Overpass API</a></th>
          <td>The demo route; the cycle network for drawing</td>
          <td>BRouter's trekking profile; international (icn) bicycle route
            relations</td>
          <td>ODbL</td></tr>
        <tr><th scope="row"><a
              href="https://www.naturalearthdata.com"
              target="_blank"
              rel="noopener noreferrer"
            >Natural Earth</a></th>
          <td>Borders, cities, rivers and lakes</td>
          <td>1:50m borders; towns of 50,000 and more</td>
          <td>Public domain</td></tr>
      </tbody>
    </table>
    <p>
      Neither the European Commission nor ECMWF is responsible for any use of
      the Copernicus information. How each is processed is in the Data tab and
      in the repository's data/README.md.
    </p>
  </section>
</template>;

export default NerdSources;
