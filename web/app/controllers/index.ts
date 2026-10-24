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

  @tracked continents = DEFAULTS.continents;
  @tracked week = DEFAULTS.week;
  @tracked temp = DEFAULTS.temp;
  @tracked heat = DEFAULTS.heat;
  @tracked rain = DEFAULTS.rain;
  @tracked borders = DEFAULTS.borders;
  @tracked cities = DEFAULTS.cities;
  @tracked relief = DEFAULTS.relief;
  @tracked water = DEFAULTS.water;
  @tracked dots = DEFAULTS.dots;
  @tracked rainy = DEFAULTS.rainy;
  @tracked route = DEFAULTS.route;
  @tracked start = DEFAULTS.start;
  @tracked km = DEFAULTS.km;
  @tracked speed = DEFAULTS.speed;
  @tracked ride = DEFAULTS.ride;
  @tracked rest = DEFAULTS.rest;
  @tracked reverse = DEFAULTS.reverse;
  @tracked day = DEFAULTS.day;
  @tracked track = DEFAULTS.track;
  @tracked name = DEFAULTS.name;
}

declare module '@ember/controller' {
  interface Registry {
    index: IndexController;
  }
}
