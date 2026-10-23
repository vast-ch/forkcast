import EmberRouter from '@embroider/router';
import config from 'wheelther/config/environment';

export default class Router extends EmberRouter {
  location = config.locationType;
  rootURL = config.rootURL;
}

Router.map(function () {
  this.route('help');
  this.route('continent', { path: '/:continent_id' });
});
