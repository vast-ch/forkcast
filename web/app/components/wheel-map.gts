import Component from '@glimmer/component';
import { service } from '@ember/service';
import Modifier from 'ember-modifier';
import { registerDestructor } from '@ember/destroyable';
import L from 'leaflet';
import type Owner from '@ember/owner';
import type AtlasService from 'forkcast/services/atlas';
import type PlannerService from 'forkcast/services/planner';
import { dayAtKm, type Trip } from 'forkcast/utils/itinerary';
import {
  temperatureRaster,
  rainDots,
  reliefRaster,
} from 'forkcast/utils/layers';
import { pointAt, type Route } from 'forkcast/utils/route';
import { climateOn, tempSwatch } from 'forkcast/utils/climate';
import { fmtShortDate } from 'forkcast/utils/format';
import type { DetailKind } from 'forkcast/services/atlas';
import {
  MAP_DETAILS,
  OWN_COLOR,
  type MapDetail,
  type RainMetric,
  type TempMetric,
} from 'forkcast/services/planner';

/** The night stops' rings and the highlighted day's stretch: a vivid purple
 * that stands out on every temperature colour (it glows a little, see
 * .wt-stop and .wt-day-stretch in app.css). */
const ROUTE_ACCENT = '#a020f0';

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
  | 'routes'
  | 'stops';

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
  trip?: Trip;
  isDrawing: boolean;
  drawnCount: number;
  highlightedDay?: number;
  /** Map details switched on in the Map section */
  details: Record<MapDetail, boolean>;
  /** How many detail files have arrived, so the map redraws when one does */
  detailFiles: number;
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
    others?: L.LayerGroup;
    overview?: L.LayerGroup;
    temp?: L.LayerGroup;
    rain?: L.LayerGroup;
    routes?: L.LayerGroup;
    stops?: L.LayerGroup;
    drawn?: L.Polyline;
    cursor?: L.CircleMarker;
  } = {};
  last: Partial<Record<string, unknown>> = {};
  rainRenderer?: L.Canvas;
  lastState?: MapState;
  fit?: { bounds: L.LatLngBounds; until: number };

  constructor(
    owner: Owner,
    args: { named: LeafletSignature['Args']['Named']; positional: [] },
  ) {
    super(owner, args);
    registerDestructor(this, () => this.map?.remove());
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
    const bbox = this.owner?.atlas.loaded[0]?.continent.bbox;
    if (bbox) {
      map.fitBounds([
        [bbox[1], bbox[0]],
        [bbox[3], bbox[2]],
      ]);
    }
    map.attributionControl.setPrefix(false);
    // The two notices the route data's licences (ODbL) want next to the map;
    // every credit and licence in full is on the help page, one click away.
    map.attributionControl.addAttribution(
      '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> · EuroVelo · <a href="/help#sources">Credits</a>',
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
    this.map = map;
    // The container keeps resizing while the page lays out (the day chart
    // appears under it a moment later); keep the map sized and the fit right.
    const ro = new ResizeObserver(() => {
      map.invalidateSize();
      if (this.fit && performance.now() < this.fit.until) {
        map.fitBounds(this.fit.bounds, FIT);
      }
    });
    ro.observe(element);
    registerDestructor(this, () => ro.disconnect());
    // The container may still be resizing as the layout settles.
    setTimeout(() => map.invalidateSize(), 0);
  }

  /** Replace a layer group with a freshly built one (`build` may leave it empty). */
  replace(key: GroupLayer, build: (group: L.LayerGroup) => void): void {
    this.layers[key]?.remove();
    const group = L.layerGroup();
    build(group);
    this.layers[key] = group.addTo(this.map!);
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

    if (this.changed('relief', `${ids}-${s.details.relief}`)) {
      this.replace('relief', (group) => {
        if (!s.details.relief) return;
        grids.forEach((g, k) => {
          const r = reliefRaster(g, grids.slice(0, k));
          L.imageOverlay(r.url, r.bounds, {
            pane: 'relief',
            interactive: false,
          }).addTo(group);
        });
      });
    }

    const filesKey = `${ids}-${s.detailFiles}`;
    if (this.changed('water', `${filesKey}-${s.details.water}`)) {
      this.replace('water', (group) => {
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
    }

    if (this.changed('labels', `${filesKey}-${s.details.cities}`)) {
      this.replace('labels', (group) => {
        if (!s.details.cities) return;
        for (const p of files('places')) {
          for (const [name, lon, lat] of p.ranges) {
            label(name, lat, lon, 'wt-range-name').addTo(group);
          }
          for (const [name, lon, lat, isCapital] of p.places) {
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
  }

  changed(key: string, value: unknown): boolean {
    if (this.last[key] === value) return false;
    this.last[key] = value;
    return true;
  }

  /** Fit the view to `bounds`, and keep it fitted while the layout settles. */
  fitTo(bounds: L.LatLngBounds) {
    this.fit = { bounds, until: performance.now() + 2000 };
    this.map!.invalidateSize();
    this.map!.fitBounds(bounds, FIT);
  }

  /** Cells per rain dot, so a dot spans at least ~9 px at the current zoom. */
  rainBlock(step: number): number {
    const pxPerDeg = (256 * 2 ** (this.map?.getZoom() ?? 5)) / 360;
    return Math.max(1, Math.ceil(9 / (step * pxPerDeg)));
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
    if (this.changed('borders', `${ids}-${s.details.borders}`)) {
      this.replace('borders', (group) => {
        if (!s.details.borders) return;
        L.geoJSON(countries, {
          pane: 'borders',
          interactive: false,
          style: { weight: 0.8, fill: false, className: 'wt-border' },
        }).addTo(group);
      });
    }
    this.syncDetails(s, ids);

    // Continents not shown yet: plain shapes that add their climate on click.
    const world = atlas.world;
    if (world && this.changed('others', `${ids}-${atlas.continents.length}`)) {
      this.replace('others', (group) => {
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
    }

    if (loaded.length) {
      const grids = loaded.map((l) => l.climate);
      const tempKey = `${ids}-${s.week}-${s.tempMetric}-${s.showTemp}`;
      if (this.changed('temp', tempKey)) {
        this.replace('temp', (group) => {
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
        });
      }
      const block = this.rainBlock(grids[0]!.step);
      const rainKey = `${ids}-${s.week}-${s.rainMetric}-${s.rainThreshold}-${s.showRain}-${block}`;
      if (this.changed('rain', rainKey)) {
        this.replace('rain', (group) => {
          if (!s.showRain) return;
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
        });
      }
    }

    // Every preset route of the shown continents, dashed; click one to pick it.
    const selectedId = s.route?.id;
    if (
      this.changed('overview', `${ids}-${selectedId}-${atlas.overview.length}`)
    ) {
      this.replace('overview', (group) => {
        const names = new Map(atlas.presets.map((r) => [r.id, r.name]));
        for (const r of atlas.overview) {
          if (r.id === selectedId || !atlas.loadedIds.includes(r.continent))
            continue;
          L.polyline(
            r.lat.map((lat, i) => [lat, r.lon[i]!] as [number, number]),
            {
              pane: 'overview',
              color: r.color,
              weight: 2.5,
              opacity: 0.75,
              dashArray: '6 5',
              className: 'wt-overview-route',
            },
          )
            .bindTooltip(names.get(r.id) ?? r.id, STICKY_TIP)
            .on(
              'click',
              this.unlessDrawing(
                () => void this.owner?.planner.selectRoute(r.id),
              ),
            )
            .addTo(group);
        }
      });
    }

    if (this.changed('route', s.route)) {
      this.replace('routes', (group) => {
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
        this.fitTo(L.latLngBounds(s.route.points.map(latLng)));
      }
    }

    if (
      this.changed('trip', s.trip) ||
      this.changed('highlight', s.highlightedDay)
    ) {
      this.replace('stops', (group) => {
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
            color: isHi ? '#111' : ROUTE_ACCENT,
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
    }

    // A double-click zooms in, except while drawing: there it finishes the route.
    if (this.changed('drawing', s.isDrawing)) {
      if (s.isDrawing) map.doubleClickZoom.disable();
      else map.doubleClickZoom.enable();
    }
    if (this.changed('drawn', `${s.isDrawing}-${s.drawnCount}`)) {
      this.layers.drawn?.remove();
      this.layers.drawn = undefined;
      map.getContainer().style.cursor = s.isDrawing ? 'crosshair' : '';
      if (s.isDrawing && s.drawnCount > 0) {
        const pts = this.owner!.planner.drawn.map(latLng);
        this.layers.drawn = L.polyline(pts, {
          color: OWN_COLOR,
          weight: 3,
          dashArray: '2 6',
          lineCap: 'round',
        }).addTo(map);
      }
    }
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
      trip: p.trip,
      isDrawing: p.isDrawing,
      drawnCount: p.drawn.length,
      highlightedDay: p.highlightedDay,
      details: Object.fromEntries(
        MAP_DETAILS.map(({ key }) => [key, p.showDetail(key)]),
      ) as Record<MapDetail, boolean>,
      detailFiles: this.atlas.details.size,
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
    if (this.planner.isDrawing && this.planner.canFinishDrawing) {
      this.planner.finishDrawing('');
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
