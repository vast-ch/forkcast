import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

/**
 * The help's one setting: Nerd mode, `?nerd=true`, which every tab keeps (the
 * parameter belongs to the parent route). It only changes the help, so it
 * isn't one of the planner's settings.
 */
export default class HelpController extends Controller {
  queryParams = ['nerd'];

  @tracked nerd = false;
}

declare module '@ember/controller' {
  interface Registry {
    help: HelpController;
  }
}
