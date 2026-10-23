import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type Transition from '@ember/routing/transition';
import type AtlasService from 'forkcast/services/atlas';
import type PlannerService from 'forkcast/services/planner';
import type IndexController from 'forkcast/controllers/index';
import { DEFAULTS, SETTING_KEYS } from 'forkcast/utils/settings';

/**
 * Settings change the URL in place, without piling up browser history.
 * Changing the continent loads its data, so it re-runs the model hook.
 */
const QUERY_PARAMS = Object.fromEntries(
  SETTING_KEYS.map((k) => [
    k,
    k === 'continent'
      ? { replace: true, refreshModel: true }
      : { replace: true },
  ]),
);

export default class IndexRoute extends Route {
  @service declare atlas: AtlasService;
  @service declare planner: PlannerService;

  queryParams = QUERY_PARAMS;

  async model(params: { continent?: string }) {
    const id = params.continent || DEFAULTS.continent;
    // An unknown continent in a link falls back to Europe.
    return (
      (await this.atlas.openContinent(id)) ??
      (await this.atlas.openContinent(DEFAULTS.continent))
    );
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
