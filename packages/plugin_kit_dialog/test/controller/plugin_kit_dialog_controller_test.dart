import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

void main() {
  test('controller starts not dirty and notifies on mutation', () {
    final runtime = PluginRuntime(plugins: [_TestGlobalPlugin('core')]);
    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings.empty(),
    );
    expect(controller.isDirty, isFalse);

    var notifications = 0;
    controller.addListener(() => notifications++);
    controller.setPluginEnabled(const PluginId('core'), false);
    expect(notifications, 1);
    expect(controller.isDirty, isTrue);
  });

  test('replaceWorking overwrites the working draft', () {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(plugins: [_TestGlobalPlugin('core')]),
      initialSettings: RuntimeSettings.empty(),
    );

    const next = RuntimeSettings(
      plugins: {PluginId('foo'): PluginConfig(enabled: true)},
    );

    controller.replaceWorking(next);
    expect(controller.draft.working, next);
  });

  test('markSaved clears dirty without losing values', () {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(plugins: [_TestGlobalPlugin('core')]),
      initialSettings: RuntimeSettings.empty(),
    );

    controller.setPluginEnabled(const PluginId('core'), false);
    expect(controller.isDirty, isTrue);

    controller.markSaved();

    expect(controller.isDirty, isFalse);
    expect(
      controller.draft.working.plugins[const PluginId('core')]?.enabled,
      isFalse,
    );
  });

  test(
    'buildPluginRowModels derives label/description/flags from runtime.plugins',
    () {
      final runtime = PluginRuntime(
        plugins: [
          _TestGlobalPlugin(
            'chat_manager',
            featureFlags: [FeatureFlag.experimental],
          ),
          _TestGlobalPlugin('core_tools', featureFlags: [FeatureFlag.locked]),
          PluginKitVisualsPlugin(
            pluginVisuals: const {
              PluginId('chat_manager'): PluginKitVisual(
                description: 'Routes chats.',
              ),
            },
          ),
        ],
      )..init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final rows = const PluginChipsBuilder()
          .build(runtime, RuntimeSettings.empty())
          .all;
      expect(rows, hasLength(3));

      expect(rows[0].pluginId, 'chat_manager');
      // No prettification: raw pluginId is the label fallback.
      expect(rows[0].label, 'chat_manager');
      expect(rows[0].description, 'Routes chats.');
      expect(rows[0].experimental, isTrue);
      expect(rows[0].locked, isFalse);
      expect(rows[0].defaultEnabled, isFalse);
      expect(rows[0].isEnabled, isFalse);

      expect(rows[1].pluginId, 'core_tools');
      expect(rows[1].label, 'core_tools');
      expect(rows[1].experimental, isFalse);
      expect(rows[1].locked, isTrue);
      expect(rows[1].defaultEnabled, isTrue);
      expect(rows[1].isEnabled, isTrue);
    },
  );

  test('stable plugin toggle off then on returns to clean draft', () {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(plugins: [_TestGlobalPlugin('auto_retry')]),
      initialSettings: RuntimeSettings.empty(),
    );

    controller.setPluginEnabled(const PluginId('auto_retry'), false);
    expect(controller.isDirty, isTrue);

    controller.setPluginEnabled(const PluginId('auto_retry'), true);
    expect(controller.isDirty, isFalse);
    expect(
      controller.draft.working.plugins.containsKey(
        const PluginId('auto_retry'),
      ),
      isFalse,
    );
  });

  test('experimental plugin toggle on then off returns to clean draft', () {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(
        plugins: [
          _TestGlobalPlugin(
            'beta_tooling',
            featureFlags: [FeatureFlag.experimental],
          ),
        ],
      ),
      initialSettings: RuntimeSettings.empty(),
    );

    controller.setPluginEnabled(const PluginId('beta_tooling'), true);
    expect(controller.isDirty, isTrue);

    controller.setPluginEnabled(const PluginId('beta_tooling'), false);
    expect(controller.isDirty, isFalse);
    expect(
      controller.draft.working.plugins.containsKey(
        const PluginId('beta_tooling'),
      ),
      isFalse,
    );
  });

  test(
    'stable plugin disabled state stays dirty because it differs from default',
    () {
      final controller = PluginKitDialogController(
        runtime: PluginRuntime(plugins: [_TestGlobalPlugin('auto_retry')]),
        initialSettings: RuntimeSettings.empty(),
      );

      controller.setPluginEnabled(const PluginId('auto_retry'), false);

      expect(controller.isDirty, isTrue);
      expect(
        controller.draft.working.plugins[const PluginId('auto_retry')]?.enabled,
        isFalse,
      );
    },
  );

  test('resetPlugin removes no-op override entries', () {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(plugins: [_TestGlobalPlugin('auto_retry')]),
      initialSettings: RuntimeSettings.empty(),
    );

    controller.setPluginEnabled(const PluginId('auto_retry'), false);
    expect(controller.isDirty, isTrue);

    controller.resetPlugin(const PluginId('auto_retry'));

    expect(controller.isDirty, isFalse);
    expect(
      controller.draft.working.plugins.containsKey(
        const PluginId('auto_retry'),
      ),
      isFalse,
    );
  });

  test('service and reset mutation methods update draft state', () {
    final initial = RuntimeSettings(
      plugins: {
        PluginId('foo'): PluginConfig(
          enabled: false,
          config: {'api_key': 'abc'},
        ),
      },
      services: {
        Pin('foo', ['agent']): ServiceSettings(
          config: {
            'model': {'name': 'baseline'},
          },
        ),
      },
    );

    final runtime = PluginRuntime(plugins: [_TestGlobalPlugin('foo')]);
    runtime.init(settings: RuntimeSettings.empty());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: initial,
    );

    controller.setPluginEnabled(const PluginId('foo'), true);
    expect(
      controller.draft.working.plugins[const PluginId('foo')]?.enabled,
      isTrue,
    );

    controller.resetPlugin(const PluginId('foo'));
    expect(
      controller.draft.working.plugins[const PluginId('foo')],
      initial.plugins[const PluginId('foo')],
    );

    controller.setServiceField(
      scopedKey: Pin('foo', ['agent']),
      fieldKey: 'model.name',
      value: 'changed',
    );
    expect(
      controller.draft.working.services[Pin('foo', ['agent'])]?.config,
      equals({
        'model': {'name': 'changed'},
      }),
    );

    controller.resetField(Pin('foo', ['agent']), 'model.name');
    final afterFieldReset =
        controller.draft.working.services[Pin('foo', ['agent'])];
    if (afterFieldReset != null) {
      expect(afterFieldReset.config, isEmpty);
    }

    controller.setServiceField(
      scopedKey: Pin('foo', ['agent']),
      fieldKey: 'model.name',
      value: 'second',
    );
    controller.resetService(Pin('foo', ['agent']));
    expect(
      controller.draft.working.services[Pin('foo', ['agent'])],
      initial.services[Pin('foo', ['agent'])],
    );

    controller.setPluginEnabled(const PluginId('foo'), true);
    expect(controller.isDirty, isTrue);

    controller.resetAll();
    expect(controller.draft.working, initial);
    expect(controller.isDirty, isFalse);
  });

  test('setServiceEnabled stores false and removes default true no-op', () {
    final runtime = PluginRuntime(plugins: [_TestGlobalPlugin('foo')]);
    runtime.init(settings: RuntimeSettings.empty());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings.empty(),
    );

    controller.setServiceEnabled(Pin('foo', ['agent']), false);
    expect(
      controller.draft.working.services[Pin('foo', ['agent'])]?.enabled,
      isFalse,
    );
    expect(controller.isDirty, isTrue);

    controller.setServiceEnabled(Pin('foo', ['agent']), true);
    expect(
      controller.draft.working.services.containsKey(Pin('foo', ['agent'])),
      isFalse,
    );
    expect(controller.isDirty, isFalse);
  });

  test(
    'setServicePriority stores override and clearing removes no-op entry',
    () {
      final runtime = PluginRuntime(plugins: [_TestGlobalPlugin('foo')]);
      runtime.init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final controller = PluginKitDialogController(
        runtime: runtime,
        initialSettings: RuntimeSettings.empty(),
      );

      controller.setServicePriority(Pin('foo', ['agent']), 350);
      expect(
        controller.draft.working.services[Pin('foo', ['agent'])]?.priority,
        350,
      );
      expect(controller.isDirty, isTrue);

      controller.setServicePriority(Pin('foo', ['agent']), null);
      expect(
        controller.draft.working.services.containsKey(Pin('foo', ['agent'])),
        isFalse,
      );
      expect(controller.isDirty, isFalse);
    },
  );

  testWidgets('editing a field back to its default prunes the service entry', (
    tester,
  ) async {
    final runtime = PluginRuntime(plugins: [_ConfigurableDefaultsPlugin()]);
    runtime.init(settings: RuntimeSettings.empty());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings.empty(),
    );

    final scopedKey = Pin('defaults_plugin', ['agent', 'model']);
    controller.setServiceField(
      scopedKey: scopedKey,
      fieldKey: 'model',
      value: 'bar',
    );
    expect(controller.draft.working.services.containsKey(scopedKey), isTrue);
    expect(controller.isDirty, isTrue);

    controller.setServiceField(
      scopedKey: scopedKey,
      fieldKey: 'model',
      value: 'foo',
    );
    expect(controller.draft.working.services.containsKey(scopedKey), isFalse);
    expect(controller.isDirty, isFalse);
  });

  test('showAllServices defaults to false and notifies on change', () {
    final controller = PluginKitDialogController(
      runtime: PluginRuntime(plugins: [_TestGlobalPlugin('foo')]),
      initialSettings: RuntimeSettings.empty(),
    );

    expect(controller.showAllServices, isFalse);

    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.showAllServices = true;
    expect(controller.showAllServices, isTrue);
    expect(notifications, 1);
  });
}

class _TestGlobalPlugin extends GlobalPlugin {
  _TestGlobalPlugin(String id, {List<FeatureFlag> featureFlags = const []})
    : _pluginId = PluginId(id),
      _featureFlags = featureFlags;

  final PluginId _pluginId;
  final List<FeatureFlag> _featureFlags;

  @override
  PluginId get pluginId => _pluginId;

  @override
  List<FeatureFlag> get featureFlags => _featureFlags;
}

class _ConfigurableDefaultsPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('defaults_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<Object>(
      ServiceId.namespaced(Namespace('agent'), 'model'),
      Object.new,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Defaults',
          fields: [
            TextConfigField(key: 'model', label: 'Model', defaultValue: 'foo'),
          ],
        ),
      },
    );
  }
}
