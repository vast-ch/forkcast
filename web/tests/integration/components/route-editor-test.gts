import { module, test } from 'qunit';
import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { click, fillIn, render } from '@ember/test-helpers';
import { setupRenderingTest } from 'forkcast/tests/helpers';
import RouteEditor from 'forkcast/components/route-editor';
import { button, field } from 'forkcast/tests/helpers/find';

class FakePlanner extends Service {
  @tracked isDrawing = true;
  @tracked snapToRoutes = true;
  @tracked canSave = false;
  @tracked draftName = 'Route 1';
  calls: string[] = [];
  toggleSnap() {
    this.snapToRoutes = !this.snapToRoutes;
  }
  undoDrawnPoint() {
    this.calls.push('undo');
  }
  cancelEditing() {
    this.calls.push('cancel');
  }
  saveEditing() {
    this.calls.push(`save ${this.draftName}`);
  }
}

module('Integration | Component | route-editor', function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.owner.register('service:planner', FakePlanner);
  });

  const planner = (owner: { lookup(name: string): unknown }) =>
    owner.lookup('service:planner') as FakePlanner;

  test('save waits for a route, then saves under the name given', async function (assert) {
    const p = planner(this.owner);
    let saved = 0;
    const onSave = () => saved++;
    await render(<template><RouteEditor @onSave={{onSave}} /></template>);

    assert.dom(field('Name')).hasValue('Route 1');
    assert.dom(button('Save route')).isDisabled();
    await fillIn(field('Name'), 'Over the pass');
    p.canSave = true;
    await click(button('Save route'));
    assert.deepEqual(p.calls, ['save Over the pass']);
    assert.strictEqual(saved, 1);
  });

  test('while drawing: undo, cancel and the snapping switch go to the planner', async function (assert) {
    const p = planner(this.owner);
    await render(<template><RouteEditor /></template>);

    assert.dom('[aria-label="Drawing a route"]').exists();
    await click(button('Undo'));
    await click(button('Cancel'));
    assert.deepEqual(p.calls, ['undo', 'cancel']);

    assert.dom('[role="switch"], input[type="checkbox"]').isChecked();
    await click('[role="switch"], input[type="checkbox"]');
    assert.false(p.snapToRoutes);
  });

  test('editing an imported route: only its name', async function (assert) {
    planner(this.owner).isDrawing = false;
    await render(<template><RouteEditor /></template>);

    assert.dom('[aria-label="Editing a route"]').exists();
    assert.dom(field('Name')).exists();
    assert.dom('[role="switch"], input[type="checkbox"]').doesNotExist();
    assert.throws(() => button('Undo'));
  });
});
