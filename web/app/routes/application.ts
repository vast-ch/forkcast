import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type AtlasService from 'wheelther/services/atlas';
import type PlannerService from 'wheelther/services/planner';

export default class ApplicationRoute extends Route {
  @service declare atlas: AtlasService;
  @service declare planner: PlannerService;

  async beforeModel() {
    await this.atlas.load();
    await this.planner.selectRoute(this.planner.routeId);
  }
}
