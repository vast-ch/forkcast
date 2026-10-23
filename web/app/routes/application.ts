import Route from '@ember/routing/route';
import { service } from '@ember/service';
import type AtlasService from 'forkcast/services/atlas';

export default class ApplicationRoute extends Route {
  @service declare atlas: AtlasService;

  async beforeModel() {
    await this.atlas.loadManifest();
  }
}
