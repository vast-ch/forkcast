import Component from '@glimmer/component';
import { service } from '@ember/service';
import type AtlasService from 'forkcast/services/atlas';
import { helpTable } from 'forkcast/utils/classes';

/** The Routes tab in Nerd mode: how the ready-made routes are built, with the built ones' figures. */
export default class NerdRoutes extends Component {
  @service declare atlas: AtlasService;

  get routes() {
    return this.atlas.presets.map((r) => ({
      name: r.name,
      km: Math.round(r.km).toLocaleString('en'),
    }));
  }

  get totalKm() {
    return Math.round(
      this.atlas.presets.reduce((s, r) => s + r.km, 0),
    ).toLocaleString('en');
  }

  <template>
    <section id="routes">
      <h2>Routes</h2>

      <h3>EuroVelo</h3>
      <ol>
        <li><strong>Relations:</strong>
          from the OpenStreetMap planet, every bicycle route relation with the
          route's ref (also one of several, as in “EV7/BI1”), or international
          and named “EuroVelo N” without one; their ways, through stages and
          countries, leaving out members marked as alternatives, variants,
          excursions or connections.</li>
        <li><strong>One path:</strong>
          the ways make a graph, and the route is its shortest path from the
          official start to the end, so a route that offers several ways (both
          banks of a river) takes the shortest. Pieces less than 1 km apart are
          joined.</li>
        <li><strong>Holes:</strong>
          pieces that don't touch are bridged by straight lines, which cost more
          than riding so the path only takes one where the mapping really has a
          hole. A hole over 3 km is routed for touring bikes with BRouter, also
          on OpenStreetMap: over land always, over the sea up to 400 km, unless
          riding round is more than 2.5 times the crossing. What stays straight
          over the sea is a ferry (not counted as riding distance), over land an
          unmapped stretch (counted).</li>
        <li><strong>Heights</strong>
          from the Copernicus GLO-90 terrain model every 50 m, averaged over 250
          m against its noise; OpenStreetMap has none.</li>
        <li><strong>Simplified</strong>
          to the points that matter for the line (30 m) or for the climbing (5
          m).</li>
      </ol>

      <h3>The demo route</h3>
      <p>
        A list of towns, geocoded with Nominatim, each leg routed by BRouter's
        “trekking” profile (touring bikes on cycle-friendly roads) and
        simplified at 40 m. Legs marked as ferries are straight and don't count
        as riding.
      </p>

      <h3>Drawing your own</h3>
      <p>
        With “Follow cycle routes” on, the app snaps each click to the nearest
        point of OpenStreetMap's international cycle routes (network
        <code>icn</code>) within 25 km, and routes between clicks along them by
        A* on a graph of the routes' ways, joined where they meet. The network
        is simplified to about 300 m, so a drawn route follows the cycle routes,
        not every bend of them. Off it, or with snapping off, clicks are joined
        by straight lines. Drawn routes have no heights.
      </p>

      <h3>The built routes</h3>
      <table class="wt-help-table {{helpTable}}">
        <caption>{{this.routes.length}}
          routes,
          {{this.totalKm}}
          km in all (riding distance, ferries not counted)</caption>
        <tbody>
          {{#each this.routes as |r|}}
            <tr><th scope="row">{{r.name}}</th><td>{{r.km}} km</td></tr>
          {{/each}}
        </tbody>
      </table>
      <p>
        Compared with EuroVelo's official tracks, ours mostly follow them. They
        differ where OpenStreetMap maps another way than the official one (EV7
        west of Lake Vänern), where a hole was filled by a different road than
        the official one (EV7 through Calabria, EV3 by Copenhagen instead of
        down Jutland), or where the official track carries a branch our single
        line from start to end leaves out (EV1's coast of Portugal, to
        Finisterre).
      </p>
    </section>
  </template>
}
