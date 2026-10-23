import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';
import type Transition from '@ember/routing/transition';
import type AtlasService from 'forkcast/services/atlas';
import type PlannerService from 'forkcast/services/planner';
import type ContinentController from 'forkcast/controllers/continent';
import { SETTING_KEYS } from 'forkcast/utils/settings';

/** Settings change the URL in place, without piling up browser history. */
const QUERY_PARAMS = Object.fromEntries(
  SETTING_KEYS.map((k) => [k, { replace: true }]),
);

export default class ContinentRoute extends Route {
  @service declare atlas: AtlasService;
  @service declare planner: PlannerService;
  @service declare router: RouterService;

  queryParams = QUERY_PARAMS;

  async model(params: { continent_id: string }, transition: Transition) {
    const continent = await this.atlas.openContinent(params.continent_id);
    if (!continent) {
      transition.abort();
      void this.router.replaceWith('index');
    }
    return continent;
  }

  setupController(
    controller: ContinentController,
    model: unknown,
    transition: Transition,
  ) {
    super.setupController(controller, model, transition);
    this.planner.qp = controller;
    void this.planner.loadSelected();
  }

  resetController(_controller: ContinentController, isExiting: boolean) {
    if (isExiting) this.planner.qp = undefined;
  }
}
