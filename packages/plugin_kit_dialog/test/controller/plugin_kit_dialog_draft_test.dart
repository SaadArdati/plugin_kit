import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

// Note: PluginKitDialogDraft is package-private, exposed via the controller
// barrel in Task 8. For Task 7 we test it directly via a relative import.
import 'package:plugin_kit_dialog/src/controller/plugin_kit_dialog_draft.dart';

void main() {
  test('initial draft is not dirty', () {
    final draft = PluginKitDialogDraft.initial(RuntimeSettings.empty());
    expect(draft.isDirty, isFalse);
    expect(draft.active, draft.working);
    expect(draft.dirtyPluginIds, isEmpty);
    expect(draft.dirtyServiceKeys, isEmpty);
  });

  test('withPluginEnabled flips dirty', () {
    final draft = PluginKitDialogDraft.initial(
      RuntimeSettings.empty(),
    ).withPluginEnabled(const PluginId('foo'), true);

    expect(draft.isDirty, isTrue);
    expect(draft.dirtyPluginIds, contains(const PluginId('foo')));
    expect(draft.working.plugins[const PluginId('foo')]?.enabled, isTrue);
    expect(draft.working.plugins[const PluginId('foo')]?.config, isEmpty);
  });

  test('resetAll restores to active', () {
    final draft = PluginKitDialogDraft.initial(
      RuntimeSettings.empty(),
    ).withPluginEnabled(const PluginId('foo'), true).resetAll();

    expect(draft.isDirty, isFalse);
    expect(draft.active, draft.working);
  });

  test('markSaved makes working the new active', () {
    final draft = PluginKitDialogDraft.initial(
      RuntimeSettings.empty(),
    ).withPluginEnabled(const PluginId('foo'), true).markSaved();

    expect(draft.isDirty, isFalse);
    expect(draft.active.plugins[const PluginId('foo')]?.enabled, isTrue);
    expect(draft.active, draft.working);
  });

  test('withServiceField writes dotted key and marks service dirty', () {
    final draft = PluginKitDialogDraft.initial(
      RuntimeSettings.empty(),
    ).withServiceField(Pin('foo', ['agent']), 'model.name', 'gpt-4.1');

    expect(draft.isDirty, isTrue);
    expect(draft.dirtyServiceKeys, contains(Pin('foo', ['agent'])));
    expect(
      draft.working.services[Pin('foo', ['agent'])]?.config,
      equals({
        'model': {'name': 'gpt-4.1'},
      }),
    );
  });

  test('resetField clears path and prunes empty parents', () {
    final draft = PluginKitDialogDraft.initial(RuntimeSettings.empty())
        .withServiceField(Pin('foo', ['agent']), 'model.name', 'gpt-4.1')
        .withServiceField(Pin('foo', ['agent']), 'model.provider', 'openai')
        .resetField(Pin('foo', ['agent']), 'model.name')
        .resetField(Pin('foo', ['agent']), 'model.provider');

    expect(draft.working.services[Pin('foo', ['agent'])]?.config, isEmpty);
  });

  test('resetService restores active service snapshot', () {
    final active = RuntimeSettings(
      services: {
        Pin('foo', ['agent']): ServiceSettings(
          config: {
            'model': {'name': 'baseline'},
          },
          priority: 7,
        ),
      },
    );

    final draft = PluginKitDialogDraft.initial(active)
        .withServiceField(Pin('foo', ['agent']), 'model.name', 'changed')
        .resetService(Pin('foo', ['agent']));

    expect(draft.isDirty, isFalse);
    expect(
      draft.working.services[Pin('foo', ['agent'])],
      active.services[Pin('foo', ['agent'])],
    );
  });

  test('resetPlugin restores active plugin snapshot', () {
    final active = RuntimeSettings(
      plugins: {
        PluginId('foo'): PluginConfig(
          enabled: false,
          config: {'api_key': '123'},
        ),
      },
    );

    final draft = PluginKitDialogDraft.initial(active)
        .withPluginEnabled(const PluginId('foo'), true)
        .resetPlugin(const PluginId('foo'));

    expect(draft.isDirty, isFalse);
    expect(
      draft.working.plugins[const PluginId('foo')],
      active.plugins[const PluginId('foo')],
    );
  });

  test('applyNoOpDeletion deletes no-op service override', () {
    final draft = PluginKitDialogDraft.initial(RuntimeSettings.empty())
        .withServiceField(Pin('foo', ['agent']), 'model', 'gpt-4.1')
        .applyNoOpDeletion(
          scopedKey: Pin('foo', ['agent']),
          defaultsByFieldKey: const {'model': 'gpt-4.1'},
        );

    expect(draft.working.services.containsKey(Pin('foo', ['agent'])), isFalse);
  });

  test('applyNoOpDeletion keeps override when unknown keys are present', () {
    final draft = PluginKitDialogDraft.initial(RuntimeSettings.empty())
        .withServiceField(Pin('foo', ['agent']), 'custom.unknown', 1)
        .applyNoOpDeletion(
          scopedKey: Pin('foo', ['agent']),
          defaultsByFieldKey: const {'model': 'gpt-4.1'},
        );

    expect(draft.working.services.containsKey(Pin('foo', ['agent'])), isTrue);
  });

  test('applyNoOpDeletion keeps override when a known field differs', () {
    final draft = PluginKitDialogDraft.initial(RuntimeSettings.empty())
        .withServiceField(Pin('foo', ['agent']), 'model', 'claude')
        .applyNoOpDeletion(
          scopedKey: Pin('foo', ['agent']),
          defaultsByFieldKey: const {'model': 'gpt-4.1'},
        );

    expect(draft.working.services.containsKey(Pin('foo', ['agent'])), isTrue);
  });
}
