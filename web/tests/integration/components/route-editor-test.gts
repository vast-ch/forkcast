import { module, test } from 'qunit';
import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { click, render } from '@ember/test-helpers';
import { setupRenderingTest } from 'forkcast/tests/helpers';
import DrawControls from 'forkcast/components/draw-controls';
import { button } from 'forkcast/tests/helpers/find';

class FakePlanner extends Service {
  @tracked snapToRoutes = true;
  @tracked canFinishDrawing = false;
  calls: string[] = [];
  toggleSnap() {
    this.snapToRoutes = !this.snapToRoutes;
  }
  undoDrawnPoint() {
    this.calls.push('undo');
  }
  cancelDrawing() {
    this.calls.push('cancel');
  }
  finishDrawing() {
    this.calls.push('finish');
  }
}

module('Integration | Component | draw-controls', function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.owner.register('service:planner', FakePlanner);
  });

  test('save waits for a route, then saves and tells the caller', async function (assert) {
    const planner = this.owner.lookup(
      'service:planner',
    ) as unknown as FakePlanner;
    let saved = 0;
    const onSave = () => saved++;
    await render(<template><DrawControls @onSave={{onSave}} /></template>);

    assert.dom(button('Save route')).isDisabled();
    planner.canFinishDrawing = true;
    await click(button('Save route'));
    assert.deepEqual(planner.calls, ['finish']);
    assert.strictEqual(saved, 1);
  });

  test('undo, cancel and the snapping switch go to the planner', async function (assert) {
    const planner = this.owner.lookup(
      'service:planner',
    ) as unknown as FakePlanner;
    await render(<template><DrawControls /></template>);

    await click(button('Undo'));
    await click(button('Cancel'));
    assert.deepEqual(planner.calls, ['undo', 'cancel']);

    assert.dom('[role="switch"], input[type="checkbox"]').isChecked();
    await click('[role="switch"], input[type="checkbox"]');
    assert.false(planner.snapToRoutes);
  });
});
