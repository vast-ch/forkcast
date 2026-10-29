import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type Transition from '@ember/routing/transition';
import type AtlasService from 'forkcast/services/atlas';
import type LastVisitService from 'forkcast/services/last-visit';
import type RouterService from '@ember/routing/router-service';
import type PlannerService from 'forkcast/services/planner';
import type IndexController from 'forkcast/controllers/index';
import { DEFAULTS, PARSE, SETTING_KEYS } from 'forkcast/utils/settings';

/**
 * Settings change the URL in place, without piling up browser history.
 * Changing the climate loads data, so it re-runs the model hook.
 */
const LOADS_DATA = ['climate'];
const QUERY_PARAMS = Object.fromEntries(
  SETTING_KEYS.map((k) => [
    k,
    LOADS_DATA.includes(k)
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

  async model(params: { climate?: string }) {
    await this.atlas.show(PARSE.climate(params.climate) ?? DEFAULTS.climate);
    return this.atlas.climateId;
  }

  /**
   * Opening Forkcast with nothing in the address picks up where you left off:
   * the last settings, and the map where you left it.
   */
  redirect(_model: unknown, transition: Transition) {
    // Looking it up starts it remembering every change.
    const lastVisit = this.lastVisit;
    if (Object.keys(transition.to?.queryParams ?? {}).length > 0) return;
    // A setting changed back to its default re-runs this too (the climate
    // refreshes the model); that's not opening Forkcast.
    if (transition.from?.name === 'index') return;
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
