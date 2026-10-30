import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';
import { DEFAULTS, SETTING_KEYS } from 'forkcast/utils/settings';

/**
 * Holds every setting as a query parameter. Ember writes a parameter to the URL
 * only while it differs from the default declared here. The planner service
 * reads and writes these; components go through the planner.
 */
export default class IndexController extends Controller {
  queryParams = SETTING_KEYS;

  @tracked climate = DEFAULTS.climate;
  @tracked week = DEFAULTS.week;
  @tracked tempMetric = DEFAULTS.tempMetric;
  @tracked showTemp = DEFAULTS.showTemp;
  @tracked showRain = DEFAULTS.showRain;
  @tracked showWind = DEFAULTS.showWind;
  @tracked borders = DEFAULTS.borders;
  @tracked relief = DEFAULTS.relief;
  @tracked water = DEFAULTS.water;
  @tracked routes = DEFAULTS.routes;
  @tracked cities = DEFAULTS.cities;
  @tracked dates = DEFAULTS.dates;
  @tracked rainMetric = DEFAULTS.rainMetric;
  @tracked rainThreshold = DEFAULTS.rainThreshold;
  @tracked routeId = DEFAULTS.routeId;
  @tracked start = DEFAULTS.start;
  @tracked kmPerDay = DEFAULTS.kmPerDay;
  @tracked speed = DEFAULTS.speed;
  @tracked rideDays = DEFAULTS.rideDays;
  @tracked restDays = DEFAULTS.restDays;
  @tracked isReversed = DEFAULTS.isReversed;
  @tracked highlightedDay = DEFAULTS.highlightedDay;
}

declare module '@ember/controller' {
  interface Registry {
    index: IndexController;
  }
}
