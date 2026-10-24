import Component from '@glimmer/component';
import { service } from '@ember/service';
import { on } from '@ember/modifier';
import { Switch } from 'frontile/forms';
import type PlannerService from 'forkcast/services/planner';
import { not } from 'forkcast/utils/helpers';

interface DrawControlsSignature {
  Args: {
    /** Called after the drawn route is saved (the phone closes its drawer) */
    onSave?: () => void;
  };
  Element: HTMLElement;
}

/** While a route is being drawn: follow cycle routes, save, undo, cancel.
 * The sidebar shows them on desktop, a bar over the map on phones. */
export default class DrawControls extends Component<DrawControlsSignature> {
  @service declare planner: PlannerService;

  toggleSnap = () => this.planner.toggleSnap();
  undoPoint = () => this.planner.undoDrawnPoint();
  cancel = () => this.planner.cancelDrawing();
  save = () => {
    this.planner.finishDrawing();
    this.args.onSave?.();
  };

  <template>
    <div
      class="flex flex-wrap items-center gap-2"
      role="toolbar"
      aria-label="Drawing a route"
      ...attributes
    >
      <Switch
        @label="Follow cycle routes"
        @size="sm"
        @isSelected={{this.planner.snapToRoutes}}
        @onChange={{this.toggleSnap}}
      />
      <button
        type="button"
        class="wt-btn is-primary"
        disabled={{not this.planner.canFinishDrawing}}
        {{on "click" this.save}}
      >Save route</button>
      <button
        type="button"
        class="wt-btn"
        {{on "click" this.undoPoint}}
      >Undo</button>
      <button
        type="button"
        class="wt-btn is-ghost"
        {{on "click" this.cancel}}
      >Cancel</button>
    </div>
  </template>
}
