import Component from '@glimmer/component';
import { service } from '@ember/service';
import type AtlasService from 'forkcast/services/atlas';

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
        <li><strong>Tracks:</strong>
          the official EuroVelo GPX files, one track per stage, including
          variants and spurs.</li>
        <li><strong>One path:</strong>
          the stages are chained into a single path from the route's start to
          its end, taking the shortest way where a route offers several. Stages
          less than 1 km apart are joined.</li>
        <li><strong>Holes:</strong>
          where consecutive stages don't touch, a straight line bridges them:
          over the sea it's a ferry (not counted as riding distance), over land
          an unmapped stretch (counted).</li>
        <li><strong>Simplified</strong>
          with Douglas–Peucker at 30 m, which keeps the shape and drops points
          on straight stretches; heights come with the tracks.</li>
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
      <table class="wt-help-table">
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
        How these compare with EuroVelo's own figures, and how much the
        simplification takes off the climbing, isn't measured yet. The routes
        are moving to OpenStreetMap alone (issue #22), which is when to measure
        them.
      </p>
    </section>
  </template>
}
