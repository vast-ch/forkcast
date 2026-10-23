import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import type Owner from '@ember/owner';

/** Phone-sized screens get a different planner layout (map first, settings in a drawer). */
const PHONE = '(max-width: 899px)';

export default class MediaService extends Service {
  @tracked isPhone: boolean;

  constructor(owner: Owner) {
    super(owner);
    const mq = window.matchMedia(PHONE);
    this.isPhone = mq.matches;
    mq.addEventListener('change', (e) => {
      this.isPhone = e.matches;
    });
  }
}

declare module '@ember/service' {
  interface Registry {
    media: MediaService;
  }
}
