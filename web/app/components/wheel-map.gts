import Component from '@glimmer/component';
import { service } from '@ember/service';
import Modifier from 'ember-modifier';
import { registerDestructor } from '@ember/destroyable';
import L from 'leaflet';
import type Owner from '@ember/owner';
import type AtlasService from 'forkcast/services/atlas';
import type PlannerService from 'forkcast/services/planner';
import type LastVisitService from 'forkcast/services/last-visit';
import {
  dayAtKm,
  milestones,
  type Milestones,
  type Trip,
} from 'forkcast/utils/itinerary';
import {
  temperatureRaster,
  rainDots,
  rainMarks,
  reliefRaster,
  type RainMark,
  isCapitalsOnly,
  isPlaceShown,
} from 'forkcast/utils/layers';
import { pointAt, type Route } from 'forkcast/utils/route';
import { climateOn, tempSwatch } from 'forkcast/utils/climate';
import { fmtShortDate } from 'forkcast/utils/format';
import type { DetailKind } from 'forkcast/services/atlas';
import {
  MAP_DETAILS,
  OWN_COLOR,
  type CityLimit,
  type MapDetail,
  type RainMetric,
  type TempMetric,
} from 'forkcast/services/planner';

/** The selected day, as everywhere in the app: its night stop's ring and its
 * stretch of route, a vivid purple that stands out on every temperature
 * colour (it glows a little, see .wt-stop.is-active and .wt-day-stretch in
 * app.css). The other stops are ringed in plain ink. */
const ROUTE_ACCENT = '#a020f0';
const STOP_RING = '#17212b';

/** Room around a route when the map is fitted to it. */
const FIT = { padding: [30, 30] as [number, number] };

/** Tooltips that follow the pointer along a shape. */
const STICKY_TIP: L.TooltipOptions = { sticky: true, direction: 'top' };

/** Map panes, bottom to top, and whether they take pointer events. The
 * selected route and the stops are in Leaflet's own overlay pane (400). */
const PANES: [name: string, zIndex: number, isInteractive: boolean][] = [
  ['land', 200, false],
  ['others', 210, true],
  ['climate', 300, false],
  // Relief shading, multiplied onto the colours (see .leaflet-relief-pane).
  ['relief', 320, false],
  ['rain', 350, false],
  ['water', 360, false],
  ['borders', 380, false],
  // Other routes: above the climate layers, below the selected route.
  ['overview', 390, true],
  // The start and the night stops, above every line (the route and the
  // selected day's stretch pass under them), below the names.
  ['stops', 420, true],
  // City and range names, above the routes so they stay readable.
  ['labels', 450, false],
];

type GroupLayer =
  | 'others'
  | 'overview'
  | 'temp'
  | 'relief'
  | 'rain'
  | 'water'
  | 'borders'
  | 'labels'
  | 'cyclenet'
  | 'drawn'
  | 'routes'
  | 'stops'
  | 'dates';

interface MapState {
  /** Quarter-month shown, 0–47, and its position in the year */
  week: number;
  phase: number;
  showTemp: boolean;
  showRain: boolean;
  tempMetric: TempMetric;
  rainMetric: RainMetric;
  rainThreshold: number;
  route?: Route;
  /** Your own routes (the selected one among them too) */
  ownRoutes: Route[];
  trip?: Trip;
  isDrawing: boolean;
  /** Drawing the selected route further: the route shown is the drawing */
  isRedrawing: boolean;
  /** The sketch (the clicks) and the line drawn from it */
  sketch: { lat: number; lon: number }[];
  drawn: { lat: number; lon: number }[];
  highlightedDay?: number;
  /** Dates over the night stops */
  dates: Milestones;
  /** Map details switched on in the Map section */
  details: Record<MapDetail, boolean>;
  /** Which city names show */
  cities: CityLimit;
  /** How many detail files have arrived, so the map redraws when one does */
  detailFiles: number;
  /** Drawing with snapping on: show the cycle network to snap to */
  showCycleNet: boolean;
}

interface LeafletSignature {
  Element: HTMLDivElement;
  Args: { Named: { map: WheelMap; state: MapState } };
}

/** Owns the Leaflet instance; `modify` re-syncs layers whenever the state changes. */
class LeafletModifier extends Modifier<LeafletSignature> {
  map?: L.Map;
  owner?: WheelMap;
  layers: {
    borders?: L.LayerGroup;
    land?: L.GeoJSON;
    relief?: L.LayerGroup;
    water?: L.LayerGroup;
    labels?: L.LayerGroup;
    cyclenet?: L.LayerGroup;
    others?: L.LayerGroup;
    overview?: L.LayerGroup;
    temp?: L.LayerGroup;
    rain?: L.LayerGroup;
    routes?: L.LayerGroup;
    stops?: L.LayerGroup;
    dates?: L.LayerGroup;
    drawn?: L.LayerGroup;
    cursor?: L.CircleMarker;
  } = {};
  last: Partial<Record<string, unknown>> = {};
  rainRenderer?: L.Canvas;
  netRenderer?: L.Canvas;
  lastState?: MapState;
  /** The view to keep while the layout settles (see setup), and until when. */
  settle?: { apply: () => void; until: number };
  /** Opened where the last visit left the map: don't fit the first route. */
  isResumed = false;
  cleanups: (() => void)[] = [];

  constructor(
    owner: Owner,
    args: { named: LeafletSignature['Args']['Named']; positional: [] },
  ) {
    super(owner, args);
    registerDestructor(this, () => this.teardown());
  }

  /** Stop everything still pending (a resize, a hover, an animation), then
   * remove the map: Leaflet throws if a timer fires on a removed map. */
  teardown(): void {
    this.cleanups.forEach((f) => f());
    const map = this.map;
    if (!map) return;
    map.stop();
    // A zoom animation ends on a 250 ms timer that remove() doesn't cancel
    // (Leaflet 1.9); with this flag off the timer does nothing.
    (map as unknown as { _animatingZoom: boolean })._animatingZoom = false;
    map.remove();
    this.map = undefined;
  }

  modify(
    element: HTMLDivElement,
    _: [],
    { map: owner, state }: LeafletSignature['Args']['Named'],
  ) {
    this.owner = owner;
    if (!this.map) this.setup(element);
    this.sync(state);
  }

  setup(element: HTMLDivElement) {
    const map = L.map(element, {
      center: [20, 0],
      zoom: 3,
      minZoom: 3,
      maxZoom: 11,
      zoomSnap: 0.5,
      worldCopyJump: false,
      attributionControl: true,
    });
    const lastVisit = this.owner?.lastVisit;
    const view = lastVisit?.isResuming ? lastVisit.view : undefined;
    if (lastVisit) lastVisit.isResuming = false;
    const bbox = this.owner?.atlas.loaded[0]?.continent.bbox;
    if (view) {
      this.keep(() => map.setView([view.lat, view.lon], view.zoom));
      this.isResumed = true;
    } else if (bbox) {
      map.fitBounds([
        [bbox[1], bbox[0]],
        [bbox[3], bbox[2]],
      ]);
    }
    map.attributionControl.setPrefix(false);
    // The two notices the route data's licences (ODbL) want next to the map;
    // every credit and licence in full is on the help page, one click away.
    map.attributionControl.addAttribution(
      '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> · EuroVelo · <a href="/help/sources">Credits</a>',
    );
    for (const [name, zIndex, isInteractive] of PANES) {
      const pane = map.createPane(name);
      pane.style.zIndex = String(zIndex);
      if (!isInteractive) pane.style.pointerEvents = 'none';
    }

    let frame = 0;
    map.on('mousemove', (e: L.LeafletMouseEvent) => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => this.owner?.onHover(e.latlng, map));
    });
    map.on('mouseout', () => this.owner?.onLeave());
    map.on('click', (e: L.LeafletMouseEvent) => {
      // Touch screens have no hover: work out what is under the tap first.
      this.owner?.onHover(e.latlng, map);
      this.owner?.onClick(e.latlng);
    });
    // Rain dots merge into bigger ones when zoomed out; re-check on every zoom.
    map.on('zoomend', () => {
      if (this.lastState) this.sync(this.lastState);
    });
    map.on('dblclick', () => this.owner?.onDoubleClick());
    // Remember the view for next time (see LastVisitService).
    map.on('moveend', () => {
      const c = map.getCenter();
      if (this.owner)
        this.owner.lastVisit.view = {
          lat: Math.round(c.lat * 1e4) / 1e4,
          lon: Math.round(c.lng * 1e4) / 1e4,
          zoom: map.getZoom(),
        };
    });
    this.map = map;
    // The container keeps resizing while the page lays out (the day chart
    // appears under it a moment later); keep the map sized and the fit right.
    const ro = new ResizeObserver(() => {
      map.invalidateSize();
      if (this.settle && performance.now() < this.settle.until) {
        this.settle.apply();
      }
    });
    ro.observe(element);
    this.cleanups.push(
      () => ro.disconnect(),
      () => cancelAnimationFrame(frame),
    );
  }

  /** Replace a layer group with a freshly built one (`build` may leave it empty). */
  replace(key: GroupLayer, build: (group: L.LayerGroup) => void): void {
    this.layers[key]?.remove();
    const group = L.layerGroup();
    build(group);
    this.layers[key] = group.addTo(this.map!);
  }

  /** Rebuild a layer group when any of `deps` differs from the last sync. */
  layer(
    key: GroupLayer,
    deps: unknown[],
    build: (group: L.LayerGroup) => void,
  ): void {
    if (this.changed(key, deps)) this.replace(key, build);
  }

  /** A click handler that does nothing while a route is being drawn. */
  unlessDrawing(f: () => void): () => void {
    return () => {
      if (!this.owner?.planner.isDrawing) f();
    };
  }

  /**
   * Relief, water and names. Water and names come in per-continent files that
   * are fetched the first time their layer is on (never while it's off); the
   * map redraws when they arrive.
   */
  syncDetails(s: MapState, ids: string): void {
    const atlas = this.owner!.atlas;
    const loaded = atlas.loaded;
    const grids = loaded.map((l) => l.climate);
    const files = <K extends DetailKind>(kind: K) =>
      loaded.flatMap((l) => {
        const data = atlas.detail(kind, l.continent.id);
        if (!data) void atlas.loadDetail(kind, l.continent.id);
        return data ? [data] : [];
      });

    this.layer('relief', [ids, s.details.relief], (group) => {
      if (!s.details.relief) return;
      grids.forEach((g, k) => {
        const r = reliefRaster(g, grids.slice(0, k));
        L.imageOverlay(r.url, r.bounds, {
          pane: 'relief',
          interactive: false,
        }).addTo(group);
      });
    });

    this.layer('water', [ids, s.detailFiles, s.details.water], (group) => {
      if (!s.details.water) return;
      for (const w of files('water')) {
        for (const lake of w.lakes) {
          L.polygon(lake.map(lonLat), {
            pane: 'water',
            interactive: false,
            stroke: false,
            fillOpacity: 1,
            className: 'wt-lake',
          }).addTo(group);
        }
        for (const river of w.rivers) {
          L.polyline(river.map(lonLat), {
            pane: 'water',
            interactive: false,
            weight: 1.2,
            className: 'wt-river',
          }).addTo(group);
        }
      }
    });

    // While drawing with snapping on, the network the clicks snap to.
    this.layer('cyclenet', [ids, s.detailFiles, s.showCycleNet], (group) => {
      if (!s.showCycleNet) return;
      const renderer = (this.netRenderer ??= L.canvas({ pane: 'water' }));
      // Black outline, white inside, like a road on a map, so the routes
      // stand apart from everything else: every outline first, then every
      // fill, so junctions stay white.
      const lines = files('cyclenet').flatMap((net) =>
        net.lines.map((line) => line.map(lonLat)),
      );
      for (const [color, weight] of [
        ['#17212b', 4],
        ['#fff', 2],
      ] as const) {
        for (const line of lines) {
          L.polyline(line, {
            renderer,
            interactive: false,
            weight,
            color,
            opacity: 1,
            lineCap: 'round',
            lineJoin: 'round',
          }).addTo(group);
        }
      }
    });

    // Only the capitals when zoomed out, so a whole continent stays readable.
    const zoom = this.map!.getZoom();
    const deps = [ids, s.detailFiles, s.cities, isCapitalsOnly(zoom)];
    this.layer('labels', deps, (group) => {
      if (s.cities === 'off') return;
      for (const p of files('places')) {
        for (const [name, lon, lat, isCapital, pop, rank] of p.places) {
          if (!isPlaceShown(s.cities, zoom, pop, rank, isCapital === 1))
            continue;
          label(
            name,
            lat,
            lon,
            isCapital ? 'wt-place is-capital' : 'wt-place',
          ).addTo(group);
        }
      }
    });
  }

  /** Whether `value` (or any item, for a list) differs from the last time. */
  changed(key: string, value: unknown): boolean {
    const last = this.last[key];
    const same = Array.isArray(value)
      ? Array.isArray(last) &&
        last.length === value.length &&
        value.every((v, i) => v === last[i])
      : last === value;
    this.last[key] = value;
    return !same;
  }

  /** Set the view with `apply`, and keep it while the layout settles. */
  keep(apply: () => void) {
    this.settle = { apply, until: performance.now() + 2000 };
    apply();
  }

  /** Fit the view to `bounds`, and keep it fitted while the layout settles. */
  fitTo(bounds: L.LatLngBounds) {
    this.map!.invalidateSize();
    this.keep(() => this.map!.fitBounds(bounds, FIT));
  }

  /** Cells per rain dot (or emoji), so they are at least `px` apart at the current zoom. */
  rainBlock(step: number, px: number): number {
    const pxPerDeg = (256 * 2 ** (this.map?.getZoom() ?? 5)) / 360;
    return Math.max(1, Math.ceil(px / (step * pxPerDeg)));
  }

  sync(s: MapState) {
    this.lastState = s;
    const map = this.map!;
    const atlas = this.owner!.atlas;
    const loaded = atlas.loaded;
    const ids = atlas.loadedIds.join(',');

    const countries = {
      type: 'FeatureCollection' as const,
      features: loaded.flatMap((l) => l.countries.features),
    };
    // The countries are also the land itself, so they always load; the
    // Borders toggle only shows or hides their outlines.
    if (this.changed('countries', ids)) {
      this.layers.land?.remove();
      this.layers.land = L.geoJSON(countries, {
        pane: 'land',
        interactive: false,
        style: { stroke: false, fillOpacity: 1, className: 'wt-land' },
      }).addTo(map);
    }
    this.layer('borders', [ids, s.details.borders], (group) => {
      if (!s.details.borders) return;
      L.geoJSON(countries, {
        pane: 'borders',
        interactive: false,
        style: { weight: 0.8, fill: false, className: 'wt-border' },
      }).addTo(group);
    });
    this.syncDetails(s, ids);

    // Continents not shown yet: plain shapes that add their climate on click.
    const world = atlas.world;
    if (world)
      this.layer('others', [ids, atlas.continents.length], (group) => {
        for (const c of atlas.continents) {
          if (atlas.loadedIds.includes(c.id)) continue;
          const rings = worldRings(world[c.id] ?? '');
          if (!rings.length) continue;
          const mb = (c.gzipBytes / 1e6).toFixed(1);
          L.polygon(rings, {
            pane: 'others',
            className: `wt-other wt-other-${c.id}`,
            weight: 1,
          })
            .bindTooltip(
              `${c.name}: click to add its climate (${mb}MB)`,
              STICKY_TIP,
            )
            .on(
              'click',
              this.unlessDrawing(() => this.owner?.planner.addContinent(c.id)),
            )
            .addTo(group);
        }
      });

    if (loaded.length) {
      const grids = loaded.map((l) => l.climate);
      // Relief and borders are the same in every climate; these aren't.
      const climate = `${ids}/${atlas.climateId}`;
      this.layer(
        'temp',
        [s.week, s.tempMetric, s.showTemp, climate],
        (group) => {
          if (!s.showTemp) return;
          // One image per continent; cells an earlier one covers are left out.
          grids.forEach((g, k) => {
            const r = temperatureRaster(
              g,
              s.phase,
              s.tempMetric,
              grids.slice(0, k),
            );
            L.imageOverlay(r.url, r.bounds, {
              pane: 'climate',
              interactive: false,
            }).addTo(group);
          });
        },
      );
      const isEmoji = s.rainMetric === 'days';
      const block = this.rainBlock(grids[0]!.step, isEmoji ? 30 : 9);
      this.layer(
        'rain',
        [climate, s.week, s.rainMetric, s.rainThreshold, s.showRain, block],
        (group) => {
          if (!s.showRain) return;
          if (isEmoji) {
            const marks = grids.flatMap((g, k) =>
              rainMarks(g, s.phase, s.rainThreshold, block, grids.slice(0, k)),
            );
            new EmojiLayer(marks).addTo(group);
            return;
          }
          const renderer = (this.rainRenderer ??= L.canvas({
            pane: 'rain',
            padding: 0.3,
          }));
          grids.forEach((g, k) => {
            for (const d of rainDots(
              g,
              s.phase,
              s.rainMetric,
              s.rainThreshold,
              block,
              grids.slice(0, k),
            )) {
              L.circle(latLng(d), {
                radius: d.radius,
                renderer,
                interactive: false,
                color: '#ffffff',
                opacity: 0.5,
                weight: 0.8,
                fillColor: '#112f6e',
                fillOpacity: 0.6,
              }).addTo(group);
            }
          });
        },
      );
    }

    // Every other route, dashed: the presets of the shown continents and your
    // own routes. Click one to pick it. The Routes toggle hides them (the
    // selected route always shows).
    const selectedId = s.route?.id;
    this.layer(
      'overview',
      [ids, selectedId, atlas.overview.length, s.ownRoutes, s.details.routes],
      (group) => {
        if (!s.details.routes) return;
        const names = new Map(atlas.presets.map((r) => [r.id, r.name]));
        const others = [
          ...atlas.overview
            .filter((r) => atlas.loadedIds.includes(r.continent))
            .map((r) => ({
              id: r.id,
              name: names.get(r.id) ?? r.id,
              color: r.color,
              line: r.lat.map((lat, i) => [lat, r.lon[i]!] as [number, number]),
            })),
          ...s.ownRoutes.map((r) => ({
            id: r.id,
            name: r.name,
            color: r.color,
            line: r.points.map(latLng),
          })),
        ];
        for (const r of others) {
          if (r.id === selectedId) continue;
          L.polyline(r.line, {
            pane: 'overview',
            color: r.color,
            weight: 2.5,
            opacity: 0.75,
            dashArray: '6 5',
            className: 'wt-overview-route',
          })
            .bindTooltip(r.name, STICKY_TIP)
            .on(
              'click',
              this.unlessDrawing(
                () => void this.owner?.planner.selectRoute(r.id),
              ),
            )
            .addTo(group);
        }
      },
    );

    // The selected route; while it's being drawn further, that's the new line
    // (the planner's route follows the drawing).
    this.layer('routes', [s.route], (group) => {
      const r = s.route;
      if (!r) return;
      const latlngs = r.points.map(latLng);
      L.polyline(latlngs, {
        color: '#fff',
        weight: 7,
        opacity: 0.9,
        interactive: false,
      }).addTo(group);
      L.polyline(latlngs, {
        color: r.color,
        weight: 4,
        interactive: false,
      }).addTo(group);
    });
    if (s.route && this.changed('fitted', s.route.id)) {
      if (this.isResumed) this.isResumed = false;
      else this.fitTo(L.latLngBounds(s.route.points.map(latLng)));
    }

    this.layer('stops', [s.trip, s.highlightedDay], (group) => {
      const { trip, route } = s;
      if (!trip || !route) return;
      const start = route.points[0]!;
      L.circleMarker(latLng(start), {
        pane: 'stops',
        radius: 6,
        color: '#fff',
        weight: 2,
        fillColor: '#111',
        fillOpacity: 1,
      })
        .bindTooltip('Start', { direction: 'top' })
        .addTo(group);
      for (const d of trip.days) {
        if (d.isRest) continue;
        const isHi = d.n === s.highlightedDay;
        const hasRestNext = trip.days[d.n]?.isRest === true;
        const m = L.circleMarker(latLng(d.sleep), {
          pane: 'stops',
          radius: isHi ? 9 : hasRestNext ? 6.5 : 4.5,
          color: isHi ? ROUTE_ACCENT : STOP_RING,
          weight: isHi ? 3 : 2,
          className: isHi ? 'wt-stop is-active' : 'wt-stop',
          fillColor: tempSwatch(d.weather.high, '#888'),
          fillOpacity: 1,
        });
        m.bindTooltip(
          `Night ${d.n} · ${fmtShortDate(d.date)}${hasRestNext ? ' · rest day next' : ''}`,
          { direction: 'top', offset: [0, -4] },
        );
        m.on('click', () => this.owner?.planner.highlightDay(d));
        m.addTo(group);
      }
      if (s.highlightedDay) {
        const d = trip.days.find((x) => x.n === s.highlightedDay);
        if (d && !d.isRest) {
          const seg = route.points.filter(
            (p) => p.km >= d.fromKm && p.km <= d.toKm,
          );
          const a = pointAt(route.points, d.fromKm);
          const b = pointAt(route.points, d.toKm);
          L.polyline([latLng(a), ...seg.map(latLng), latLng(b)], {
            color: ROUTE_ACCENT,
            weight: 6,
            opacity: 0.95,
            interactive: false,
            className: 'wt-day-stretch',
          }).addTo(group);
        }
      }
    });

    // Where the rider is as each month (or week) begins, over that night's stop.
    this.layer('dates', [s.trip, s.dates], (group) => {
      const { trip } = s;
      if (!trip) return;
      for (const { day, label: text } of milestones(trip, s.dates)) {
        label(text, day.sleep.lat, day.sleep.lon, 'wt-stop-date').addTo(group);
      }
    });

    // A double-click zooms in, except while drawing: there it finishes the route.
    if (this.changed('drawing', s.isDrawing)) {
      if (s.isDrawing) map.doubleClickZoom.disable();
      else map.doubleClickZoom.enable();
      map.getContainer().style.cursor = s.isDrawing ? 'crosshair' : '';
    }
    // While drawing: the clicks as a thin dashed sketch, the route made from
    // them (matched to the cycle routes, or straight) over it. A route drawn
    // further is the selected route already, so it isn't drawn twice.
    this.layer('drawn', [s.drawn, s.sketch.length, s.isRedrawing], (group) => {
      if (!s.isDrawing || !s.sketch.length) return;
      L.polyline(s.sketch.map(latLng), {
        color: '#5d6b78',
        weight: 1.5,
        dashArray: '3 5',
        interactive: false,
      }).addTo(group);
      for (const p of s.sketch) {
        L.circleMarker(latLng(p), {
          radius: 3,
          color: '#fff',
          weight: 1,
          fillColor: '#5d6b78',
          fillOpacity: 1,
          interactive: false,
        }).addTo(group);
      }
      if (s.isRedrawing) return;
      L.polyline(s.drawn.map(latLng), {
        color: OWN_COLOR,
        weight: 4,
        opacity: 0.9,
        lineCap: 'round',
        lineJoin: 'round',
        interactive: false,
      }).addTo(group);
    });
  }
}

/**
 * Rainy-day emoji drawn into map tiles: text on a canvas, so thousands of them
 * stay cheap, at the same size in pixels at every zoom.
 */
class EmojiLayer extends L.GridLayer {
  constructor(readonly marks: RainMark[]) {
    super({ pane: 'rain', updateWhenZooming: false });
  }

  createTile(coords: L.Coords): HTMLCanvasElement {
    const size = this.getTileSize();
    const tile = document.createElement('canvas');
    const ratio = window.devicePixelRatio || 1;
    tile.width = size.x * ratio;
    tile.height = size.y * ratio;
    const ctx = tile.getContext('2d')!;
    ctx.scale(ratio, ratio);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    // Clouds are white and grey: a soft shadow keeps them apart from pale land.
    ctx.shadowColor = 'rgb(0 0 0 / 0.45)';
    ctx.shadowBlur = 3;
    const map = this._map;
    const origin = coords.scaleBy(size);
    // Emoji near the edge spill into the next tile: draw those too.
    const margin = 16;
    for (const m of this.marks) {
      const p = map.project([m.lat, m.lon], coords.z).subtract(origin);
      if (
        p.x < -margin ||
        p.y < -margin ||
        p.x > size.x + margin ||
        p.y > size.y + margin
      )
        continue;
      ctx.font = `${m.tier.px}px sans-serif`;
      ctx.fillText(m.tier.emoji, p.x, p.y);
    }
    return tile;
  }
}

/** A [lon, lat] pair from the data files as Leaflet's [lat, lng]. */
const lonLat = ([lon, lat]: [number, number]): [number, number] => [lat, lon];

/** A map label: the name as text (never HTML), in the labels pane. */
function label(name: string, lat: number, lon: number, className: string) {
  const html = document.createElement('span');
  html.textContent = name;
  return L.marker([lat, lon], {
    pane: 'labels',
    interactive: false,
    keyboard: false,
    icon: L.divIcon({ className, html, iconSize: [0, 0] }),
  });
}

/** A point as Leaflet's [lat, lng]. */
const latLng = (p: { lat: number; lon: number }): [number, number] => [
  p.lat,
  p.lon,
];

/**
 * Rings of a continent from world.json, whose SVG paths use x = lon + 180 and
 * y = 90 − lat ("M x,y L x,y … Z" per ring).
 */

function worldRings(d: string): [number, number][][] {
  return d
    .split('M')
    .filter(Boolean)
    .map((ring) =>
      ring
        .replace('Z', '')
        .split('L')
        .map((pt) => {
          const [x, y] = pt.split(',').map(Number);
          return [90 - y!, x! - 180] as [number, number];
        }),
    );
}

interface WheelMapSignature {
  Element: HTMLDivElement;
}

export default class WheelMap extends Component<WheelMapSignature> {
  @service declare atlas: AtlasService;
  @service declare planner: PlannerService;
  @service('last-visit') declare lastVisit: LastVisitService;

  get state(): MapState {
    const p = this.planner;
    return {
      week: p.week,
      phase: p.weekSlot.phase,
      showTemp: p.showTemp,
      showRain: p.showRain,
      tempMetric: p.tempMetric,
      rainMetric: p.rainMetric,
      rainThreshold: p.rainThreshold,
      route: p.route,
      ownRoutes: p.ownRoutes,
      trip: p.trip,
      isDrawing: p.isDrawing,
      isRedrawing: p.isRedrawing,
      sketch: [...p.sketch],
      drawn: p.drawn,
      highlightedDay: p.highlightedDay,
      dates: p.dates,
      details: Object.fromEntries(
        MAP_DETAILS.map(({ key }) => [key, p[key]]),
      ) as Record<MapDetail, boolean>,
      cities: p.cities,
      detailFiles: this.atlas.details.size,
      showCycleNet: p.isDrawing && p.snapToRoutes,
    };
  }

  onHover = (latlng: L.LatLng, map: L.Map) => {
    const grid = this.atlas.climate;
    if (!grid) return;
    const lat = latlng.lat;
    const lon = latlng.lng;
    const climate = grid.covers(lat, lon)
      ? grid.at(
          this.planner.weekSlot.phase,
          lat,
          lon,
          this.planner.rainThreshold,
        )
      : null;
    let onRoute: NonNullable<PlannerService['hover']>['onRoute'];
    const route = this.planner.route;
    const trip = this.planner.trip;
    if (route && !this.planner.isDrawing) {
      // Nearest route point within ~14 px of the pointer.
      const cursor = map.latLngToContainerPoint(latlng);
      let best = Infinity;
      let bestKm = -1;
      const bounds = map.getBounds().pad(0.1);
      for (const p of route.points) {
        if (!bounds.contains(latLng(p))) continue;
        const pt = map.latLngToContainerPoint(latLng(p));
        const d = (pt.x - cursor.x) ** 2 + (pt.y - cursor.y) ** 2;
        if (d < best) {
          best = d;
          bestKm = p.km;
        }
      }
      if (bestKm >= 0 && best < 14 * 14) {
        const point = pointAt(route.points, bestKm);
        const day = trip ? dayAtKm(trip, bestKm) : undefined;
        onRoute = {
          km: bestKm,
          point,
          day,
          weather: day
            ? climateOn(grid, day.date, point, this.planner.rainThreshold)
            : undefined,
        };
      }
    }
    this.planner.hover = { lat, lon, climate, onRoute };
  };

  onLeave = () => {
    this.planner.hover = undefined;
  };

  onClick = (latlng: L.LatLng) => {
    if (this.planner.isDrawing) {
      this.planner.addDrawnPoint(latlng.lat, latlng.lng);
      return;
    }
    const day = this.planner.hover?.onRoute?.day;
    if (day) this.planner.highlightDay(day);
  };

  onDoubleClick = () => {
    if (this.planner.isDrawing && this.planner.canSave) {
      this.planner.saveEditing();
    }
  };

  get weekLabel() {
    return this.planner.weekSlot.label;
  }

  <template>
    <div
      class="wt-map h-full w-full"
      aria-label="Map of the climate around {{this.weekLabel}} and routes"
      {{LeafletModifier map=this state=this.state}}
      ...attributes
    ></div>
  </template>
}
