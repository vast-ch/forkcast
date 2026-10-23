import Component from '@glimmer/component';
import { service } from '@ember/service';
import Modifier from 'ember-modifier';
import { registerDestructor } from '@ember/destroyable';
import L from 'leaflet';
import type Owner from '@ember/owner';
import type AtlasService from 'forkcast/services/atlas';
import type PlannerService from 'forkcast/services/planner';
import { dayAtKm, type Trip } from 'forkcast/utils/itinerary';
import { temperatureRaster, rainDots } from 'forkcast/utils/layers';
import { pointAt, type Route } from 'forkcast/utils/route';
import { tempColor } from 'forkcast/utils/climate';

/** Ring around each night's stop: a vivid purple that stands out on every
 * temperature colour (it glows a little, see .wt-stop in app.css). */
const STOP_RING = '#a020f0';

interface MapState {
  /** Quarter-month shown, 0–47, and its position in the year */
  week: number;
  phase: number;
  showTemp: boolean;
  showRain: boolean;
  tempMetric: string;
  rainMetric: string;
  rainThreshold: number;
  route?: Route;
  trip?: Trip;
  isDrawing: boolean;
  drawnCount: number;
  highlightedDay?: number;
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
    borders?: L.GeoJSON;
    land?: L.GeoJSON;
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
      doubleClickZoom: false,
    });
    const bbox = this.owner?.atlas.loaded[0]?.continent.bbox;
    if (bbox) {
      map.fitBounds([
        [bbox[1], bbox[0]],
        [bbox[3], bbox[2]],
      ]);
    }
    map.attributionControl.setPrefix(false);
    // Full credits on wide screens; a short line with a link to the help page's
    // sources on phones, where the full text would cover the map.
    map.attributionControl.addAttribution(
      '<span class="wt-attr-full">Climate: contains modified <a href="https://cds.climate.copernicus.eu/datasets/reanalysis-era5-land" target="_blank" rel="noopener">Copernicus Climate Change Service</a> information 2026 (ERA5-Land), <a href="https://crudata.uea.ac.uk/cru/data/hrg/" target="_blank" rel="noopener">CRU TS 4.10</a> · Borders: Natural Earth · Routes: contains information from <a href="https://www.eurovelo.com" target="_blank" rel="noopener">EuroVelo GPX tracks</a> downloaded 2026-10-23, under the <a href="https://opendatacommons.org/licenses/odbl/1-0/" target="_blank" rel="noopener">ODbL</a>; © OpenStreetMap contributors, BRouter</span>' +
        '<span class="wt-attr-short">Contains modified Copernicus C3S information 2026 · CRU · EuroVelo (ODbL) · © OpenStreetMap · <a href="/help#sources">Sources</a></span>',
    );
    map.createPane('land').style.zIndex = '200';
    map.createPane('others').style.zIndex = '210';
    map.createPane('climate').style.zIndex = '300';
    map.createPane('rain').style.zIndex = '350';
    map.createPane('borders').style.zIndex = '380';
    // Other routes: above the climate layers, below the selected route (400).
    map.createPane('overview').style.zIndex = '390';
    map.getPane('borders')!.style.pointerEvents = 'none';
    map.getPane('climate')!.style.pointerEvents = 'none';
    map.getPane('rain')!.style.pointerEvents = 'none';
    map.getPane('land')!.style.pointerEvents = 'none';

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
        map.fitBounds(this.fit.bounds, { padding: [30, 30] });
      }
    });
    ro.observe(element);
    registerDestructor(this, () => ro.disconnect());
    // The container may still be resizing as the layout settles.
    setTimeout(() => map.invalidateSize(), 0);
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
    this.map!.fitBounds(bounds, { padding: [30, 30] });
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

    if (this.changed('countries', ids)) {
      this.layers.land?.remove();
      this.layers.borders?.remove();
      const features = loaded.flatMap((l) => l.countries.features);
      const all = { type: 'FeatureCollection' as const, features };
      this.layers.land = L.geoJSON(all, {
        pane: 'land',
        interactive: false,
        style: { stroke: false, fillOpacity: 1, className: 'wt-land' },
      }).addTo(map);
      this.layers.borders = L.geoJSON(all, {
        pane: 'borders',
        interactive: false,
        style: { weight: 0.8, fill: false, className: 'wt-border' },
      }).addTo(map);
    }

    // Continents not shown yet: plain shapes that add their climate on click.
    if (
      atlas.world &&
      this.changed('others', `${ids}-${atlas.continents.length}`)
    ) {
      this.layers.others?.remove();
      const group = L.layerGroup();
      for (const c of atlas.continents) {
        if (atlas.loadedIds.includes(c.id)) continue;
        const rings = worldRings(atlas.world[c.id] ?? '');
        if (!rings.length) continue;
        const mb = (c.gzipBytes / 1e6).toFixed(1);
        L.polygon(rings, {
          pane: 'others',
          className: `wt-other wt-other-${c.id}`,
          weight: 1,
        })
          .bindTooltip(`${c.name}: click to add its climate (${mb} MB)`, {
            sticky: true,
            direction: 'top',
          })
          .on('click', () => {
            if (!this.owner?.planner.isDrawing) this.owner?.loadContinent(c.id);
          })
          .addTo(group);
      }
      this.layers.others = group.addTo(map);
    }

    if (loaded.length) {
      const grids = loaded.map((l) => l.climate);
      const tempKey = `${ids}-${s.week}-${s.tempMetric}-${s.showTemp}`;
      if (this.changed('temp', tempKey)) {
        this.layers.temp?.remove();
        this.layers.temp = undefined;
        if (s.showTemp) {
          // One image per continent; cells an earlier one covers are left out.
          const group = L.layerGroup();
          grids.forEach((g, k) => {
            const r = temperatureRaster(
              g,
              s.phase,
              s.tempMetric as 'high' | 'low',
              grids.slice(0, k),
            );
            L.imageOverlay(r.url, r.bounds, {
              pane: 'climate',
              interactive: false,
            }).addTo(group);
          });
          this.layers.temp = group.addTo(map);
        }
      }
      const block = this.rainBlock(grids[0]!.step);
      const rainKey = `${ids}-${s.week}-${s.rainMetric}-${s.rainThreshold}-${s.showRain}-${block}`;
      if (this.changed('rain', rainKey)) {
        this.layers.rain?.remove();
        this.layers.rain = undefined;
        if (s.showRain) {
          const renderer = (this.rainRenderer ??= L.canvas({
            pane: 'rain',
            padding: 0.3,
          }));
          const group = L.layerGroup();
          grids.forEach((g, k) => {
            for (const d of rainDots(
              g,
              s.phase,
              s.rainMetric as 'mm' | 'days',
              s.rainThreshold,
              block,
              grids.slice(0, k),
            )) {
              L.circle([d.lat, d.lon], {
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
          this.layers.rain = group.addTo(map);
        }
      }
    }

    // Every preset route of the shown continents, dashed; click one to pick it.
    const selectedId = s.route?.id;
    if (
      this.changed('overview', `${ids}-${selectedId}-${atlas.overview.length}`)
    ) {
      this.layers.overview?.remove();
      const group = L.layerGroup();
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
          .bindTooltip(names.get(r.id) ?? r.id, {
            sticky: true,
            direction: 'top',
          })
          .on('click', () => {
            if (!this.owner?.planner.isDrawing)
              void this.owner?.planner.selectRoute(r.id);
          })
          .addTo(group);
      }
      this.layers.overview = group.addTo(map);
    }

    if (this.changed('route', s.route)) {
      this.layers.routes?.remove();
      const group = L.layerGroup();
      const r = s.route;
      if (r) {
        const latlngs = r.points.map((p) => [p.lat, p.lon] as [number, number]);
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
      }
      this.layers.routes = group.addTo(map);
      if (s.route && this.changed('fitted', s.route.id)) {
        this.fitTo(L.latLngBounds(s.route.points.map((p) => [p.lat, p.lon])));
      }
    }

    if (
      this.changed('trip', s.trip) ||
      this.changed('highlight', s.highlightedDay)
    ) {
      this.layers.stops?.remove();
      const group = L.layerGroup();
      const trip = s.trip;
      if (trip && s.route) {
        const start = s.route.points[0]!;
        L.circleMarker([start.lat, start.lon], {
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
          const m = L.circleMarker([d.sleep.lat, d.sleep.lon], {
            radius: isHi ? 9 : hasRestNext ? 6.5 : 4.5,
            color: isHi ? '#111' : STOP_RING,
            weight: isHi ? 3 : 2,
            className: isHi ? 'wt-stop is-active' : 'wt-stop',
            fillColor: Number.isNaN(d.weather.high)
              ? '#888'
              : tempColor(d.weather.high),
            fillOpacity: 1,
          });
          const date = d.date.toLocaleDateString(undefined, {
            day: 'numeric',
            month: 'short',
          });
          m.bindTooltip(
            `Night ${d.n} · ${date}${hasRestNext ? ' · rest day next' : ''}`,
            { direction: 'top', offset: [0, -4] },
          );
          m.on('click', () => this.owner?.planner.set('highlightedDay', d.n));
          m.addTo(group);
        }
        if (s.highlightedDay) {
          const d = trip.days.find((x) => x.n === s.highlightedDay);
          if (d && !d.isRest) {
            const seg = s.route.points.filter(
              (p) => p.km >= d.fromKm && p.km <= d.toKm,
            );
            const a = pointAt(s.route.points, d.fromKm);
            const b = pointAt(s.route.points, d.toKm);
            L.polyline(
              [
                [a.lat, a.lon],
                ...seg.map((p) => [p.lat, p.lon] as [number, number]),
                [b.lat, b.lon],
              ],
              { color: '#111', weight: 6, opacity: 0.85, interactive: false },
            ).addTo(group);
          }
        }
      }
      this.layers.stops = group.addTo(map);
    }

    if (this.changed('drawn', `${s.isDrawing}-${s.drawnCount}`)) {
      this.layers.drawn?.remove();
      this.layers.drawn = undefined;
      element(map).style.cursor = s.isDrawing ? 'crosshair' : '';
      if (s.isDrawing && s.drawnCount > 0) {
        const pts = this.owner!.planner.drawn.map(
          (p) => [p.lat, p.lon] as [number, number],
        );
        this.layers.drawn = L.polyline(pts, {
          color: '#b5179e',
          weight: 3,
          dashArray: '2 6',
          lineCap: 'round',
        }).addTo(map);
      }
    }
  }
}

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

function element(map: L.Map): HTMLElement {
  return map.getContainer();
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
    };
  }

  onHover = (latlng: L.LatLng, map: L.Map) => {
    const grid = this.atlas.climate;
    if (!grid) return;
    const lat = latlng.lat;
    const lon = latlng.lng;
    const month = grid.covers(lat, lon)
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
        if (!bounds.contains([p.lat, p.lon])) continue;
        const pt = map.latLngToContainerPoint([p.lat, p.lon]);
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
            ? grid.on(
                day.date,
                point.lat,
                point.lon,
                this.planner.rainThreshold,
                point.ele,
              )
            : undefined,
        };
      }
    }
    this.planner.hover = { lat, lon, month, onRoute };
  };

  loadContinent = (id: string) => {
    this.planner.addContinent(id);
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
    if (day) {
      this.planner.set('highlightedDay', day.n);
      this.planner.showDate(day.date);
    }
  };

  onDoubleClick = () => {
    if (this.planner.isDrawing && this.planner.drawn.length >= 2) {
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
