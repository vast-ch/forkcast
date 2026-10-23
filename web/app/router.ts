import EmberRouter from '@embroider/router';
import config from 'forkcast/config/environment';

export default class Router extends EmberRouter {
  location = config.locationType;
  rootURL = config.rootURL;
}

Router.map(function () {
  this.route('help');
  // Anything else (old /europe links, typos) opens the planner.
  this.route('not-found', { path: '/*path' });
});
