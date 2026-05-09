import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class TestGlobalPlugin extends GlobalPlugin {
  @override
  final PluginId pluginId;
  final List<String> lifecycleCalls = [];

  TestGlobalPlugin(String id) : pluginId = PluginId(id);

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
  }

  @override
  void attach(GlobalPluginContext context) {
    lifecycleCalls.add('attach');
  }

  @override
  Future<void> detach(GlobalPluginContext context) {
    lifecycleCalls.add('detach');
    return Future<void>.value();
  }
}

class _CustomGlobalContext extends GlobalPluginContext {
  final String label;

  _CustomGlobalContext({
    required super.registry,
    required super.bus,
    required super.sessions,
    required this.label,
  });
}

class TestSessionPlugin extends SessionPlugin {
  @override
  final PluginId pluginId;
  final List<String> lifecycleCalls = [];

  TestSessionPlugin(String id) : pluginId = PluginId(id);

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
  }

  @override
  void attach(SessionPluginContext context) {
    lifecycleCalls.add('attach');
  }

  @override
  Future<void> detach(SessionPluginContext context) {
    lifecycleCalls.add('detach');
    return Future<void>.value();
  }
}

void main() {
  late PluginRuntimeManager manager;

  setUp(() {
    manager = PluginRuntimeManager();
  });

  tearDown(() async {
    await manager.dispose();
  });

  group('Plugin registration', () {
    test('addPlugin delegates to runtime', () {
      final plugin = TestGlobalPlugin('g1');
      manager.addPlugin(plugin);
      expect(manager.runtime.plugins, contains(plugin));
    });

    test('addPlugins registers multiple plugins', () {
      final g = TestGlobalPlugin('g1');
      final s = TestSessionPlugin('s1');
      manager.addPlugins([g, s]);
      expect(manager.runtime.plugins, hasLength(2));
    });

    test('addPlugin rejects duplicate pluginIds', () {
      manager.addPlugin(TestGlobalPlugin('dup'));
      expect(
        () => manager.addPlugin(TestSessionPlugin('dup')),
        throwsStateError,
      );
    });

    test('inline plugins parameter registers the list', () {
      final g = TestGlobalPlugin('g1');
      final s = TestSessionPlugin('s1');
      final inlineManager = PluginRuntimeManager(plugins: [g, s]);
      expect(inlineManager.runtime.plugins, containsAll([g, s]));
    });
  });

  group('Initialization', () {
    test('init initializes runtime', () {
      manager.addPlugin(TestGlobalPlugin('g1'));
      manager.init();
      expect(manager.runtime.globalContext, isA<GlobalPluginContext>());
    });

    test('init with initialSettings applies settings before runtime init', () {
      final settings = RuntimeSettings(
        plugins: {const PluginId('g1'): const PluginConfig(enabled: false)},
      );
      final plugin = TestGlobalPlugin('g1');
      manager.addPlugin(plugin);
      manager.init(initialSettings: settings);

      expect(manager.settings, equals(settings));
      expect(plugin.lifecycleCalls, isEmpty); // disabled
    });

    test('init without initialSettings uses empty default', () {
      final plugin = TestGlobalPlugin('g1');
      manager.addPlugin(plugin);
      manager.init();
      expect(plugin.lifecycleCalls, ['register', 'attach']);
    });

    test(
      'init with globalContextFactory builds custom global context',
      () async {
        final customManager =
            PluginRuntimeManager<_CustomGlobalContext, SessionPluginContext>();

        customManager.init(
          globalContextFactory: (registry, bus, sessions) =>
              _CustomGlobalContext(
                registry: registry,
                bus: bus,
                sessions: sessions,
                label: 'custom-global',
              ),
        );

        expect(customManager.runtime.globalContext.label, 'custom-global');

        await customManager.dispose();
      },
    );

    test(
      'init without globalContextFactory throws when G is a custom type',
      () {
        final customManager =
            PluginRuntimeManager<_CustomGlobalContext, SessionPluginContext>();

        expect(() => customManager.init(), throwsStateError);
      },
    );
  });

  group('Session creation', () {
    test('createSession delegates to runtime', () async {
      manager.addPlugin(TestSessionPlugin('s1'));
      manager.init();

      final session = await manager.createSession();
      expect(manager.runtime.sessions, hasLength(1));
      expect(session.context, isA<SessionPluginContext>());
    });

    test('createSession uses manager settings by default', () async {
      final plugin = TestSessionPlugin('s1');
      manager.addPlugin(plugin);
      manager.init();

      await manager.createSession();
      expect(plugin.lifecycleCalls, ['register', 'attach']);
    });

    test('createSession accepts explicit settings', () async {
      final plugin = TestSessionPlugin('s1');
      manager.addPlugin(plugin);
      manager.init();

      await manager.createSession(
        settings: RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
        ),
      );

      // Plugin disabled by explicit settings: not registered or attached
      expect(plugin.lifecycleCalls, isEmpty);
    });

    test('createSession with contextFactory', () async {
      manager.addPlugin(TestSessionPlugin('s1'));
      manager.init();

      final session = await manager.createSession(
        contextFactory: (registry, sessionBus, globalBus) {
          return SessionPluginContext(
            registry: registry,
            bus: sessionBus,
            globalBus: globalBus,
            extras: {'test': 'value'},
          );
        },
      );

      expect(session.context.extras['test'], 'value');
    });
  });

  group('Settings', () {
    test('settings stream emits on updateSettings', () async {
      manager.addPlugin(TestGlobalPlugin('g1'));
      manager.init();

      final emissions = <RuntimeSettings>[];
      manager.settingsStream.listen(emissions.add);

      final newSettings = RuntimeSettings(
        plugins: {const PluginId('g1'): const PluginConfig(enabled: true)},
      );
      await manager.updateSettings(newSettings);

      expect(emissions, hasLength(1));
      expect(emissions.first, equals(newSettings));
    });

    test('updateSettingsSnapshot updates settings without reconciliation', () {
      final plugin = TestGlobalPlugin('g1');
      manager.addPlugin(plugin);
      manager.init();
      plugin.lifecycleCalls.clear();

      final emissions = <RuntimeSettings>[];
      manager.settingsStream.listen(emissions.add);

      final newSettings = RuntimeSettings(
        services: {
          Pin('g1', ['some_svc']): ServiceSettings(config: {'key': 'val'}),
        },
      );
      manager.updateSettingsSnapshot(newSettings);

      expect(manager.settings, equals(newSettings));
      expect(
        emissions,
        [newSettings],
        reason:
            'updateSettingsSnapshot should emit the new snapshot exactly once',
      );
      // No lifecycle calls: no reconciliation
      expect(plugin.lifecycleCalls, isEmpty);
    });

    test('updateSettingsSnapshot is no-op for identical settings', () {
      manager.init();
      final emissions = <RuntimeSettings>[];
      manager.settingsStream.listen(emissions.add);

      manager.updateSettingsSnapshot(manager.settings);
      expect(emissions, isEmpty);
    });

    test('resetSettings returns to empty default', () async {
      manager.init();

      final customSettings = RuntimeSettings(
        plugins: {const PluginId('x'): const PluginConfig(enabled: false)},
      );
      manager.updateSettingsSnapshot(customSettings);
      expect(manager.settings, equals(customSettings));

      manager.resetSettings();
      expect(manager.settings.plugins, isEmpty);
      expect(manager.settings.services, isEmpty);
    });
  });

  group('Enabled plugins', () {
    test('enabledPlugins returns only enabled plugins', () {
      final g1 = TestGlobalPlugin('g1');
      final s1 = TestSessionPlugin('s1');
      manager.addPlugins([g1, s1]);
      manager.init(
        initialSettings: RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
        ),
      );

      expect(manager.enabledPlugins.map((p) => p.pluginId), [
        const PluginId('g1'),
      ]);
    });

    test('enabledPluginIds returns set of IDs', () {
      manager.addPlugins([TestGlobalPlugin('g1'), TestSessionPlugin('s1')]);
      manager.init();
      expect(manager.enabledPluginIds, {
        const PluginId('g1'),
        const PluginId('s1'),
      });
    });

    test('isPluginEnabled checks individual plugin', () {
      manager.addPlugin(TestGlobalPlugin('g1'));
      manager.init(
        initialSettings: RuntimeSettings(
          plugins: {const PluginId('g1'): const PluginConfig(enabled: false)},
        ),
      );
      expect(manager.isPluginEnabled(const PluginId('g1')), isFalse);
    });
  });

  group('Settings reconciliation', () {
    test('updateSettings reconciles global plugins', () async {
      final plugin = TestGlobalPlugin('g1');
      manager.addPlugin(plugin);
      manager.init();
      plugin.lifecycleCalls.clear();

      // Disable the plugin
      await manager.updateSettings(
        RuntimeSettings(
          plugins: {const PluginId('g1'): const PluginConfig(enabled: false)},
        ),
      );

      expect(plugin.lifecycleCalls, ['detach']);
    });

    test('updateSettings reconciles session plugins', () async {
      final plugin = TestSessionPlugin('s1');
      manager.addPlugin(plugin);
      manager.init();

      await manager.createSession();
      expect(plugin.lifecycleCalls, ['register', 'attach']);

      // Disable the session plugin
      await manager.updateSettings(
        RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
        ),
      );
      expect(plugin.lifecycleCalls, ['register', 'attach', 'detach']);

      // Re-enable to verify lifecycle-driven reconciliation, not just
      // settings map mutation.
      await manager.updateSettings(
        RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: true)},
        ),
      );
      expect(plugin.lifecycleCalls, [
        'register',
        'attach',
        'detach',
        'register',
        'attach',
      ]);
    });

    test(
      'updateSettings invokes plugin.detach on session plugin disable',
      () async {
        // Regression: session reconciliation used to skip plugin.attach/detach,
        // only touching registered StatefulPluginServices. Direct bus
        // subscriptions in attach leaked on disable. See
        // PluginRuntime._reconcilePluginsOnSettingsUpdate.
        final plugin = TestSessionPlugin('s1');
        manager.addPlugin(plugin);
        manager.init();

        await manager.createSession();
        plugin.lifecycleCalls.clear();

        await manager.updateSettings(
          RuntimeSettings(
            plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
          ),
        );

        expect(plugin.lifecycleCalls, contains('detach'));
      },
    );

    test(
      'updateSettings invokes plugin.register + plugin.attach on session plugin enable',
      () async {
        // Regression: session reconciliation's enable path used to register
        // the plugin but skip plugin.attach, so direct bus subscriptions
        // were never set up.
        final plugin = TestSessionPlugin('s1');
        manager.addPlugin(plugin);
        manager.init(
          initialSettings: RuntimeSettings(
            plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
          ),
        );

        await manager.createSession();
        plugin.lifecycleCalls.clear();

        await manager.updateSettings(
          RuntimeSettings(
            plugins: {const PluginId('s1'): const PluginConfig(enabled: true)},
          ),
        );

        expect(plugin.lifecycleCalls, ['register', 'attach']);
      },
    );
  });

  group('Dispose', () {
    test('dispose closes settings stream', () async {
      manager.init();

      final doneCompleter = Completer<void>();
      manager.settingsStream.listen(
        (_) {},
        onDone: () {
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete();
          }
        },
      );

      await manager.dispose();

      await expectLater(
        doneCompleter.future.timeout(const Duration(milliseconds: 250)),
        completes,
      );
    });

    test('dispose disposes runtime', () async {
      final plugin = TestGlobalPlugin('g1');
      manager.addPlugin(plugin);
      manager.init();
      plugin.lifecycleCalls.clear();

      await manager.dispose();
      expect(plugin.lifecycleCalls, ['detach']);
    });
  });
}
