import EmberRouter from '@embroider/router';
import config from 'forkcast/config/environment';

export default class Router extends EmberRouter {
  location = config.locationType;
  rootURL = config.rootURL;
}

Router.map(function () {
  // /help is the first section; /help/<id> the others (app/help-sections.json).
  this.route('help', function () {
    this.route('section', { path: '/:section' });
  });
  this.route('changelog');
  // Anything else (old /europe links, typos) opens the planner.
  this.route('not-found', { path: '/*path' });
});
