import Service, { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';
import type Owner from '@ember/owner';

/** Where the map was looking: its centre and zoom. */
export interface MapView {
  lat: number;
  lon: number;
  zoom: number;
}

interface Saved {
  /** The planner's settings as the URL's query string, without the `?` */
  settings: string;
  view?: MapView;
}

/**
 * Where you left off, kept in this browser's storage and nowhere else: the
 * planner's settings (the URL's query string) and the map's view. Opening
 * Forkcast with nothing in the address picks up from there; a link with
 * settings in it opens what it says.
 */
export default class LastVisitService extends Service {
  @service declare router: RouterService;

  /** The localStorage key (tests use their own). */
  get storageKey(): string {
    return 'forkcast:last-visit';
  }

  #saved: Saved = this.#load();
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
      this.#save({ ...this.#saved, settings: i < 0 ? '' : url.slice(i + 1) });
    });
  }

  /** The settings of the last visit, as a URL, or undefined if there are none. */
  get url(): string | undefined {
    return this.#saved.settings ? `/?${this.#saved.settings}` : undefined;
  }

  get view(): MapView | undefined {
    return this.#saved.view;
  }
  set view(view: MapView) {
    this.#save({ ...this.#saved, view });
  }

  #load(): Saved {
    try {
      const raw = JSON.parse(
        localStorage.getItem(this.storageKey) ?? '{}',
      ) as Partial<Saved> | null;
      const v = raw?.view;
      const isView =
        typeof v?.lat === 'number' &&
        typeof v.lon === 'number' &&
        typeof v.zoom === 'number';
      return {
        settings: typeof raw?.settings === 'string' ? raw.settings : '',
        ...(isView && { view: v }),
      };
    } catch {
      return { settings: '' };
    }
  }

  /** Remember `saved`; if the browser won't store it, it's only kept for
   * this visit. */
  #save(saved: Saved): void {
    this.#saved = saved;
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(saved));
    } catch {
      // Storage full or switched off: nothing to pick up next time.
    }
  }
}

declare module '@ember/service' {
  interface Registry {
    'last-visit': LastVisitService;
  }
}
