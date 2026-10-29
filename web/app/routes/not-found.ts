import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type RouterService from '@ember/routing/router-service';

/** Unknown paths go to the planner. */
export default class NotFoundRoute extends Route {
  @service declare router: RouterService;

  beforeModel() {
    void this.router.replaceWith('index');
  }
}
