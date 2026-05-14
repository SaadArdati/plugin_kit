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
    super.extras,
  });

  @override
  _CustomGlobalContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
    List<PluginSession<SessionPluginContext>>? sessions,
    String? label,
  }) {
    return _CustomGlobalContext(
      registry: registry ?? this.registry.copy(),
      bus: bus ?? this.bus,
      extras: extras ?? this.extras,
      sessions: sessions ?? this.sessions,
      label: label ?? this.label,
    );
  }
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
  // #docregion runtime-test-runtime
  late PluginRuntime runtime;
  // #enddocregion runtime-test-runtime

  setUp(() {
    runtime = PluginRuntime();
  });

  tearDown(() async {
    await runtime.dispose();
  });

  group('Plugin registration', () {
    test('addPlugin delegates to runtime', () {
      final plugin = TestGlobalPlugin('g1');
      runtime.addPlugin(plugin);
      expect(runtime.plugins, contains(plugin));
    });

    test('addPlugins registers multiple plugins', () {
      final g = TestGlobalPlugin('g1');
      final s = TestSessionPlugin('s1');
      runtime.addPlugins([g, s]);
      expect(runtime.plugins, hasLength(2));
    });

    test('addPlugin rejects duplicate pluginIds', () {
      runtime.addPlugin(TestGlobalPlugin('dup'));
      expect(
        () => runtime.addPlugin(TestSessionPlugin('dup')),
        throwsStateError,
      );
    });

    test('inline plugins parameter registers the list', () {
      final g = TestGlobalPlugin('g1');
      final s = TestSessionPlugin('s1');
      final inlineRuntime = PluginRuntime(plugins: [g, s]);
      expect(inlineRuntime.plugins, containsAll([g, s]));
    });
  });

  group('Initialization', () {
    test('init initializes runtime', () {
      runtime.addPlugin(TestGlobalPlugin('g1'));
      runtime.init();
      expect(runtime.globalContext, isA<GlobalPluginContext>());
    });

    test('init with explicit settings applies them before runtime init', () {
      final settings = RuntimeSettings(
        plugins: {const PluginId('g1'): const PluginConfig(enabled: false)},
      );
      final plugin = TestGlobalPlugin('g1');
      runtime.addPlugin(plugin);
      runtime.init(settings: settings);

      expect(runtime.settings, equals(settings));
      expect(plugin.lifecycleCalls, isEmpty); // disabled
    });

    test('init without explicit settings uses empty default', () {
      final plugin = TestGlobalPlugin('g1');
      runtime.addPlugin(plugin);
      runtime.init();
      expect(plugin.lifecycleCalls, ['register', 'attach']);
    });

    test(
      'init with globalContextFactory builds custom global context',
      () async {
        final customRuntime =
            PluginRuntime<_CustomGlobalContext, SessionPluginContext>();

        customRuntime.init(
          globalContextFactory: (registry, bus, sessions) =>
              _CustomGlobalContext(
                registry: registry,
                bus: bus,
                sessions: sessions,
                label: 'custom-global',
              ),
        );

        expect(customRuntime.globalContext.label, 'custom-global');

        await customRuntime.dispose();
      },
    );

    test(
      'init without globalContextFactory throws when G is a custom type',
      () {
        final customRuntime =
            PluginRuntime<_CustomGlobalContext, SessionPluginContext>();

        expect(() => customRuntime.init(), throwsStateError);
      },
    );
  });

  group('Session creation', () {
    test('createSession delegates to runtime', () async {
      runtime.addPlugin(TestSessionPlugin('s1'));
      runtime.init();

      final session = await runtime.createSession();
      expect(runtime.sessions, hasLength(1));
      expect(session.context, isA<SessionPluginContext>());
    });

    test('createSession uses runtime settings by default', () async {
      final plugin = TestSessionPlugin('s1');
      runtime.addPlugin(plugin);
      runtime.init();

      await runtime.createSession();
      expect(plugin.lifecycleCalls, ['register', 'attach']);
    });

    test('createSession accepts explicit settings', () async {
      final plugin = TestSessionPlugin('s1');
      runtime.addPlugin(plugin);
      runtime.init();

      await runtime.createSession(
        settings: RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
        ),
      );

      // Plugin disabled by explicit settings: not registered or attached
      expect(plugin.lifecycleCalls, isEmpty);
    });

    test('createSession with contextFactory', () async {
      runtime.addPlugin(TestSessionPlugin('s1'));
      runtime.init();

      // #docregion runtime-test-session
      final session = await runtime.createSession(
        contextFactory: (registry, sessionBus, globalBus) {
          return SessionPluginContext(
            registry: registry,
            bus: sessionBus,
            globalBus: globalBus,
            extras: {'test': 'value'},
          );
        },
      );
      // #enddocregion runtime-test-session

      expect(session.context.extras['test'], 'value');
    });
  });

  group('Settings', () {
    test('settings stream emits on updateSettings', () async {
      runtime.addPlugin(TestGlobalPlugin('g1'));
      runtime.init();

      final emissions = <RuntimeSettings>[];
      runtime.settingsStream.listen(emissions.add);

      final newSettings = RuntimeSettings(
        plugins: {const PluginId('g1'): const PluginConfig(enabled: true)},
      );
      await runtime.updateSettings(newSettings);

      expect(emissions, hasLength(1));
      expect(emissions.first, equals(newSettings));
    });

    test('updateSettingsSnapshot updates settings without reconciliation', () {
      final plugin = TestGlobalPlugin('g1');
      runtime.addPlugin(plugin);
      runtime.init();
      plugin.lifecycleCalls.clear();

      final emissions = <RuntimeSettings>[];
      runtime.settingsStream.listen(emissions.add);

      final newSettings = RuntimeSettings(
        services: {
          Pin('g1', ['some_svc']): ServiceSettings(config: {'key': 'val'}),
        },
      );
      runtime.updateSettingsSnapshot(newSettings);

      expect(runtime.settings, equals(newSettings));
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
      runtime.init();
      final emissions = <RuntimeSettings>[];
      runtime.settingsStream.listen(emissions.add);

      runtime.updateSettingsSnapshot(runtime.settings);
      expect(emissions, isEmpty);
    });

    test('resetSettings returns to empty default', () async {
      runtime.init();

      final customSettings = RuntimeSettings(
        plugins: {const PluginId('x'): const PluginConfig(enabled: false)},
      );
      runtime.updateSettingsSnapshot(customSettings);
      expect(runtime.settings, equals(customSettings));

      runtime.resetSettings();
      expect(runtime.settings.plugins, isEmpty);
      expect(runtime.settings.services, isEmpty);
    });
  });

  group('Enabled plugins', () {
    test('enabledPlugins returns only enabled plugins', () {
      final g1 = TestGlobalPlugin('g1');
      final s1 = TestSessionPlugin('s1');
      runtime.addPlugins([g1, s1]);
      runtime.init(
        settings: RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
        ),
      );

      expect(runtime.enabledPlugins.map((p) => p.pluginId), [
        const PluginId('g1'),
      ]);
    });

    test('enabledPluginIds returns set of IDs', () {
      runtime.addPlugins([TestGlobalPlugin('g1'), TestSessionPlugin('s1')]);
      runtime.init();
      expect(runtime.enabledPluginIds, {
        const PluginId('g1'),
        const PluginId('s1'),
      });
    });

    test('isPluginEnabled checks individual plugin', () {
      runtime.addPlugin(TestGlobalPlugin('g1'));
      runtime.init(
        settings: RuntimeSettings(
          plugins: {const PluginId('g1'): const PluginConfig(enabled: false)},
        ),
      );
      expect(runtime.isPluginEnabled(const PluginId('g1')), isFalse);
    });
  });

  group('Settings reconciliation', () {
    test('updateSettings reconciles global plugins', () async {
      final plugin = TestGlobalPlugin('g1');
      runtime.addPlugin(plugin);
      runtime.init();
      plugin.lifecycleCalls.clear();

      // Disable the plugin
      await runtime.updateSettings(
        RuntimeSettings(
          plugins: {const PluginId('g1'): const PluginConfig(enabled: false)},
        ),
      );

      expect(plugin.lifecycleCalls, ['detach']);
    });

    test('updateSettings reconciles session plugins', () async {
      final plugin = TestSessionPlugin('s1');
      runtime.addPlugin(plugin);
      runtime.init();

      await runtime.createSession();
      expect(plugin.lifecycleCalls, ['register', 'attach']);

      // Disable the session plugin
      await runtime.updateSettings(
        RuntimeSettings(
          plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
        ),
      );
      expect(plugin.lifecycleCalls, ['register', 'attach', 'detach']);

      // Re-enable to verify lifecycle-driven reconciliation, not just
      // settings map mutation.
      await runtime.updateSettings(
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
        runtime.addPlugin(plugin);
        runtime.init();

        await runtime.createSession();
        plugin.lifecycleCalls.clear();

        await runtime.updateSettings(
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
        runtime.addPlugin(plugin);
        runtime.init(
          settings: RuntimeSettings(
            plugins: {const PluginId('s1'): const PluginConfig(enabled: false)},
          ),
        );

        await runtime.createSession();
        plugin.lifecycleCalls.clear();

        await runtime.updateSettings(
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
      runtime.init();

      final doneCompleter = Completer<void>();
      runtime.settingsStream.listen(
        (_) {},
        onDone: () {
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete();
          }
        },
      );

      await runtime.dispose();

      await expectLater(
        doneCompleter.future.timeout(const Duration(milliseconds: 250)),
        completes,
      );
    });

    test('dispose disposes runtime', () async {
      final plugin = TestGlobalPlugin('g1');
      runtime.addPlugin(plugin);
      runtime.init();
      plugin.lifecycleCalls.clear();

      await runtime.dispose();
      expect(plugin.lifecycleCalls, ['detach']);
    });
  });
}
