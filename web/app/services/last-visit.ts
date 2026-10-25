import Service, { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';
import type Owner from '@ember/owner';
import { isText, stored } from 'forkcast/utils/stored';

/** Where the map was looking: its centre and zoom. */
export interface MapView {
  lat: number;
  lon: number;
  zoom: number;
}

function parseView(raw: unknown): MapView | undefined {
  const v = raw as Partial<MapView> | null;
  return typeof v?.lat === 'number' &&
    typeof v.lon === 'number' &&
    typeof v.zoom === 'number'
    ? { lat: v.lat, lon: v.lon, zoom: v.zoom }
    : undefined;
}

/**
 * Where you left off, kept in this browser's storage: the planner's settings
 * and the map's view. Opening Forkcast with nothing in the address picks up
 * from there; a link with settings in it opens what it says.
 */
export default class LastVisitService extends Service {
  @service declare router: RouterService;

  /** The planner's last query string, without the `?`. Every setting is in
   * it, so none needs remembering on its own. */
  @stored('last-plan', isText) plan = '';
  @stored('map-view', parseView) view?: MapView;
  /** Set when this visit picks up where the last one left off, until the map
   * has taken the saved view (instead of fitting the route). */
  isResuming = false;

  constructor(owner: Owner) {
    super(owner);
    // Every settings change replaces the URL, so this sees each one.
    this.router.on('routeDidChange', () => {
      if (this.router.currentRouteName !== 'index') return;
      const url = this.router.currentURL ?? '';
      const i = url.indexOf('?');
      this.plan = i < 0 ? '' : url.slice(i + 1);
    });
  }

  /** The last visit's settings as a URL, or undefined if there are none. */
  get url(): string | undefined {
    return this.plan ? `/?${this.plan}` : undefined;
  }
}

declare module '@ember/service' {
  interface Registry {
    'last-visit': LastVisitService;
  }
}
