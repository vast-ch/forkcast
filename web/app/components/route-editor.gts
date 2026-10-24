import Component from '@glimmer/component';
import { service } from '@ember/service';
import { on } from '@ember/modifier';
import { Input, Switch } from 'frontile/forms';
import type PlannerService from 'forkcast/services/planner';
import { not } from 'forkcast/utils/helpers';

interface RouteEditorSignature {
  Args: {
    /** Called after saving (the phone closes its drawer) */
    onSave?: () => void;
  };
  Element: HTMLElement;
}

/**
 * While drawing a route or editing one of yours: its name, and while drawing
 * also follow cycle routes and undo; then save or cancel. The sidebar shows it
 * on desktop, a bar over the map on phones while drawing.
 */
export default class RouteEditor extends Component<RouteEditorSignature> {
  @service declare planner: PlannerService;

  toggleSnap = () => this.planner.toggleSnap();
  undoPoint = () => this.planner.undoDrawnPoint();
  setName = (name: string) => (this.planner.draftName = name);
  cancel = () => this.planner.cancelEditing();
  save = () => {
    this.planner.saveEditing();
    this.args.onSave?.();
  };

  get label() {
    return this.planner.isDrawing ? 'Drawing a route' : 'Editing a route';
  }

  <template>
    <div
      class="flex flex-wrap items-center gap-2"
      role="toolbar"
      aria-label={{this.label}}
      ...attributes
    >
      <Input
        @label="Name"
        @size="sm"
        @value={{this.planner.draftName}}
        @onChange={{this.setName}}
        class="w-full"
      />
      {{#if this.planner.isDrawing}}
        <Switch
          @label="Follow cycle routes"
          @size="sm"
          @isSelected={{this.planner.snapToRoutes}}
          @onChange={{this.toggleSnap}}
        />
      {{/if}}
      <button
        type="button"
        class="wt-btn is-primary"
        disabled={{not this.planner.canSave}}
        {{on "click" this.save}}
      >Save route</button>
      {{#if this.planner.isDrawing}}
        <button
          type="button"
          class="wt-btn"
          {{on "click" this.undoPoint}}
        >Undo</button>
      {{/if}}
      <button
        type="button"
        class="wt-btn is-ghost"
        {{on "click" this.cancel}}
      >Cancel</button>
    </div>
  </template>
}
