import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type Transition from '@ember/routing/transition';
import type AtlasService from 'forkcast/services/atlas';
import type LastVisitService from 'forkcast/services/last-visit';
import type RouterService from '@ember/routing/router-service';
import type PlannerService from 'forkcast/services/planner';
import type IndexController from 'forkcast/controllers/index';
import { DEFAULTS, SETTING_KEYS } from 'forkcast/utils/settings';

/**
 * Settings change the URL in place, without piling up browser history.
 * Changing the continents loads their data, so it re-runs the model hook.
 */
const QUERY_PARAMS = Object.fromEntries(
  SETTING_KEYS.map((k) => [
    k,
    k === 'continents'
      ? { replace: true, refreshModel: true }
      : { replace: true },
  ]),
);

export default class IndexRoute extends Route {
  @service declare atlas: AtlasService;
  @service declare planner: PlannerService;
  @service declare router: RouterService;
  @service('last-visit') declare lastVisit: LastVisitService;

  queryParams = QUERY_PARAMS;

  async model(params: { continents?: string }) {
    const ids = (params.continents || DEFAULTS.continents).split(',');
    const shown = await this.atlas.show(ids);
    // A link with only unknown continents falls back to Europe.
    if (shown.length === 0) await this.atlas.show([DEFAULTS.continents]);
    return this.atlas.loadedIds;
  }

  /**
   * Opening Forkcast with nothing in the address picks up where you left off:
   * the last settings, and the map where you left it.
   */
  redirect(_model: unknown, transition: Transition) {
    // Looking it up starts it remembering every change.
    const lastVisit = this.lastVisit;
    if (Object.keys(transition.to?.queryParams ?? {}).length > 0) return;
    lastVisit.isResuming = true;
    const url = lastVisit.url;
    if (url) void this.router.replaceWith(url);
  }

  setupController(
    controller: IndexController,
    model: unknown,
    transition: Transition,
  ) {
    super.setupController(controller, model, transition);
    this.planner.qp = controller;
    void this.planner.loadSelected();
  }

  resetController(_controller: IndexController, isExiting: boolean) {
    if (isExiting) this.planner.qp = undefined;
  }
}
