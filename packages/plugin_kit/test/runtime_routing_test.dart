import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class TestGlobalPlugin extends GlobalPlugin {
  @override
  final PluginId pluginId;
  final List<String> lifecycleCalls = [];
  final bool _experimental;
  @override
  final Set<PluginId> dependencies;

  TestGlobalPlugin(
    String id, {
    bool experimental = false,
    this.dependencies = const {},
  }) : pluginId = PluginId(id),
       _experimental = experimental;

  @override
  List<FeatureFlag> get featureFlags =>
      _experimental ? const [.experimental] : const [];

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
    registry.registerSingleton<String>(
      ServiceId('${pluginId}_service'),
      'Instance from $pluginId',
      priority: 100,
    );
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

  void clearCalls() => lifecycleCalls.clear();
}

class ThrowingGlobalPlugin extends GlobalPlugin {
  @override
  final PluginId pluginId;

  ThrowingGlobalPlugin(String id) : pluginId = PluginId(id);

  @override
  void attach(GlobalPluginContext context) {
    throw Exception('$pluginId attach failed');
  }
}

class ThrowingSessionPlugin extends SessionPlugin {
  @override
  final PluginId pluginId;

  ThrowingSessionPlugin(String id) : pluginId = PluginId(id);

  @override
  void attach(SessionPluginContext context) {
    throw Exception('$pluginId attach failed');
  }
}

class CustomGlobalContext extends GlobalPluginContext {
  final String custom;

  CustomGlobalContext({
    required super.registry,
    required super.bus,
    required this.custom,
    super.sessions,
  });
}

class CustomSessionContext extends SessionPluginContext {
  final String custom;

  CustomSessionContext({
    required super.registry,
    required super.bus,
    required super.globalBus,
    required this.custom,
  });
}

class TestSessionPlugin extends SessionPlugin {
  @override
  final PluginId pluginId;
  final List<String> lifecycleCalls = [];
  final bool _experimental;

  TestSessionPlugin(String id, {bool experimental = false})
    : pluginId = PluginId(id),
      _experimental = experimental;

  @override
  List<FeatureFlag> get featureFlags =>
      _experimental ? const [.experimental] : const [];

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
    registry.registerSingleton<String>(
      ServiceId('${pluginId}_service'),
      'Instance from $pluginId',
      priority: 100,
    );
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

  void clearCalls() => lifecycleCalls.clear();
}

void main() {
  late PluginRuntime runtime;

  setUp(() {
    runtime = PluginRuntime.empty();
  });

  tearDown(() async {
    try {
      await runtime.dispose();
    } on PluginLifecycleException {
      // Some tests register ThrowingGlobalPlugin which fails on detach too.
    }
  });

  group('Plugin routing', () {
    test('init only processes GlobalPlugins', () {
      final global = TestGlobalPlugin('config');
      final session = TestSessionPlugin('chat');

      runtime.addPlugin(global);
      runtime.addPlugin(session);
      runtime.init();

      expect(global.lifecycleCalls, ['register', 'attach']);
      expect(session.lifecycleCalls, isEmpty);
    });

    test('createSession only processes SessionPlugins', () async {
      final global = TestGlobalPlugin('config');
      final session = TestSessionPlugin('chat');

      runtime.addPlugin(global);
      runtime.addPlugin(session);
      runtime.init();
      global.clearCalls();

      await runtime.createSession(settings: RuntimeSettings());

      expect(session.lifecycleCalls, ['register', 'attach']);
      expect(global.lifecycleCalls, isEmpty);
    });

    test('addPlugin rejects duplicate pluginIds', () {
      runtime.addPlugin(TestGlobalPlugin('dup'));
      expect(
        () => runtime.addPlugin(TestSessionPlugin('dup')),
        throwsStateError,
      );
    });

    test('globalPlugins returns only GlobalPlugin instances', () {
      runtime.addPlugin(TestGlobalPlugin('g1'));
      runtime.addPlugin(TestSessionPlugin('s1'));
      runtime.addPlugin(TestGlobalPlugin('g2'));

      expect(runtime.globalPlugins.map((p) => p.pluginId), ['g1', 'g2']);
    });

    test('sessionPlugins returns only SessionPlugin instances', () {
      runtime.addPlugin(TestGlobalPlugin('g1'));
      runtime.addPlugin(TestSessionPlugin('s1'));
      runtime.addPlugin(TestSessionPlugin('s2'));

      expect(runtime.sessionPlugins.map((p) => p.pluginId), ['s1', 's2']);
    });
  });

  group('Global plugin lifecycle', () {
    test('disabled global plugins are not registered or attached', () {
      final plugin = TestGlobalPlugin('disabled');
      runtime.addPlugin(plugin);
      runtime.init(
        settings: RuntimeSettings(
          plugins: {PluginId('disabled'): PluginConfig(enabled: false)},
        ),
      );
      expect(plugin.lifecycleCalls, isEmpty);
    });

    test('experimental global plugins are disabled by default', () {
      final plugin = TestGlobalPlugin('exp', experimental: true);
      runtime.addPlugin(plugin);
      runtime.init();
      expect(plugin.lifecycleCalls, isEmpty);
    });

    test('explicit settings override experimental default', () {
      final plugin = TestGlobalPlugin('exp', experimental: true);
      runtime.addPlugin(plugin);
      runtime.init(
        settings: RuntimeSettings(
          plugins: {PluginId('exp'): PluginConfig(enabled: true)},
        ),
      );
      expect(plugin.lifecycleCalls, ['register', 'attach']);
    });

    test('dispose detaches enabled global plugins', () async {
      final plugin = TestGlobalPlugin('config');
      runtime.addPlugin(plugin);
      runtime.init();
      plugin.clearCalls();

      await runtime.dispose();
      expect(plugin.lifecycleCalls, ['detach']);
    });

    test('dispose does not detach disabled global plugins', () async {
      final enabled = TestGlobalPlugin('enabled');
      final disabled = TestGlobalPlugin('disabled');
      runtime.addPlugin(enabled);
      runtime.addPlugin(disabled);
      runtime.init(
        settings: RuntimeSettings(
          plugins: {PluginId('disabled'): PluginConfig(enabled: false)},
        ),
      );
      enabled.clearCalls();
      disabled.clearCalls();

      await runtime.dispose();
      expect(enabled.lifecycleCalls, ['detach']);
      expect(disabled.lifecycleCalls, isEmpty);
    });

    test('globalContext is accessible after init', () {
      runtime.init();
      expect(runtime.globalContext, isA<GlobalPluginContext>());
      expect(runtime.globalContext.bus, same(runtime.globalBus));
    });
  });

  group('Session lifecycle', () {
    test(
      'session plugin register/attach called during createSession',
      () async {
        final session = TestSessionPlugin('chat');
        runtime.addPlugin(session);
        runtime.init();

        await runtime.createSession(settings: RuntimeSettings());

        expect(session.lifecycleCalls, ['register', 'attach']);
      },
    );

    test('session dispose detaches session plugins', () async {
      final plugin = TestSessionPlugin('chat');
      runtime.addPlugin(plugin);
      runtime.init();

      final pluginSession = await runtime.createSession(
        settings: RuntimeSettings(),
      );
      plugin.clearCalls();

      await pluginSession.dispose();
      expect(plugin.lifecycleCalls, ['detach']);
    });

    test('createSession before init throws StateError', () {
      runtime.addPlugin(TestSessionPlugin('chat'));

      expect(
        () => runtime.createSession(settings: RuntimeSettings()),
        throwsStateError,
      );
    });

    test('multiple sessions are tracked', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      await runtime.createSession(settings: RuntimeSettings());
      await runtime.createSession(settings: RuntimeSettings());
      expect(runtime.sessions, hasLength(2));
    });

    test('createSession with custom contextFactory', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      SessionPluginContext? capturedCtx;
      await runtime.createSession(
        settings: RuntimeSettings(),
        contextFactory: (registry, sessionBus, globalBus) {
          final ctx = SessionPluginContext(
            registry: registry,
            bus: sessionBus,
            globalBus: globalBus,
            extras: {'custom': 'value'},
          );
          capturedCtx = ctx;
          return ctx;
        },
      );

      expect(capturedCtx, isNotNull);
      expect(capturedCtx!.extras['custom'], 'value');
    });

    test('createSession without contextFactory uses default', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      final session = await runtime.createSession(settings: RuntimeSettings());

      expect(session.context, isA<SessionPluginContext>());
      expect(session.context.bus, isA<EventBus>());
      expect(session.context.bus, isNot(same(runtime.globalBus)));
      final ctx = session.context;
      expect(ctx.globalBus, same(runtime.globalBus));
    });
  });

  group('Global and session bus isolation', () {
    test('global bus events do not reach session buses', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      var sessionReceived = false;
      await runtime.createSession(
        settings: RuntimeSettings(),
        contextFactory: (registry, sessionBus, globalBus) {
          sessionBus.on<String>((_) {
            sessionReceived = true;
          });
          return SessionPluginContext(
            registry: registry,
            bus: sessionBus,
            globalBus: globalBus,
          );
        },
      );

      await runtime.globalBus.emit<String>(event: 'global-only');

      expect(
        sessionReceived,
        isFalse,
        reason: 'global bus events should not cascade to session buses',
      );
    });

    test('internal global-bus events do not reach session buses', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      var sessionReceived = false;
      await runtime.createSession(
        settings: RuntimeSettings(),
        contextFactory: (registry, sessionBus, globalBus) {
          sessionBus.on<String>((_) {
            sessionReceived = true;
          });
          return SessionPluginContext(
            registry: registry,
            bus: sessionBus,
            globalBus: globalBus,
          );
        },
      );

      await runtime.globalBus.emitInternal<String>(event: 'internal-only');

      expect(
        sessionReceived,
        isFalse,
        reason: 'internal global events should not cross the scope boundary',
      );
    });

    test(
      'sessions.emit reaches every session bus without firing global handlers',
      () async {
        runtime.addPlugin(TestSessionPlugin('chat'));
        runtime.init();

        var globalReceived = false;
        runtime.globalBus.on<String>((_) {
          globalReceived = true;
        });

        final s1Received = <String>[];
        final s2Received = <String>[];

        await runtime.createSession(
          settings: RuntimeSettings(),
          contextFactory: (registry, sessionBus, globalBus) {
            sessionBus.on<String>((e) {
              s1Received.add(e.event);
            });
            return SessionPluginContext(
              registry: registry,
              bus: sessionBus,
              globalBus: globalBus,
            );
          },
        );
        await runtime.createSession(
          settings: RuntimeSettings(),
          contextFactory: (registry, sessionBus, globalBus) {
            sessionBus.on<String>((e) {
              s2Received.add(e.event);
            });
            return SessionPluginContext(
              registry: registry,
              bus: sessionBus,
              globalBus: globalBus,
            );
          },
        );

        await runtime.globalContext.sessions.emit<String>('broadcast');

        expect(s1Received, ['broadcast']);
        expect(s2Received, ['broadcast']);
        expect(
          globalReceived,
          isFalse,
          reason: 'sessions.emit should not invoke global-bus handlers',
        );
      },
    );
  });

  group('Session to global communication', () {
    test('session plugin can emit to globalBus via context', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      String? globalReceived;
      runtime.globalBus.on<String>((e) {
        globalReceived = e.event;
      });

      final session = await runtime.createSession(settings: RuntimeSettings());

      await session.context.globalBus.emit<String>(event: 'from-session');

      expect(globalReceived, 'from-session');
    });
  });

  group('GlobalPluginContext.sessions', () {
    test('global context sees active sessions', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      expect(runtime.globalContext.sessions, isEmpty);

      await runtime.createSession(settings: RuntimeSettings());

      expect(runtime.globalContext.sessions, hasLength(1));
    });

    test('disposed session is removed from runtime.sessions', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      final session = await runtime.createSession(settings: RuntimeSettings());
      expect(runtime.sessions, hasLength(1));

      await session.dispose();
      expect(runtime.sessions, isEmpty);
    });

    test('disposed session is removed from globalContext.sessions', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      final session = await runtime.createSession(settings: RuntimeSettings());
      expect(runtime.globalContext.sessions, hasLength(1));

      await session.dispose();
      expect(runtime.globalContext.sessions, isEmpty);
    });

    test('runtime.dispose works after individual session dispose', () async {
      runtime.addPlugin(TestSessionPlugin('chat'));
      runtime.init();

      final session1 = await runtime.createSession(settings: RuntimeSettings());
      await runtime.createSession(settings: RuntimeSettings());

      // Dispose one session manually
      await session1.dispose();
      expect(runtime.sessions, hasLength(1));

      // runtime.dispose should not crash (no double-dispose, no ConcurrentModification)
      await runtime.dispose();
      expect(runtime.sessions, isEmpty);
    });
  });

  group('Attach-failure isolation', () {
    test('global plugin attach failure does not block other plugins', () {
      final thrower = ThrowingGlobalPlugin('thrower');
      final healthy = TestGlobalPlugin('healthy');

      runtime.addPlugin(thrower);
      runtime.addPlugin(healthy);

      expect(() => runtime.init(), throwsA(isA<PluginLifecycleException>()));

      // The healthy plugin should still be attached despite thrower crashing
      expect(healthy.lifecycleCalls, contains('attach'));
    });

    test(
      'session plugin attach failure does not block other plugins',
      () async {
        final thrower = ThrowingSessionPlugin('thrower');
        final healthy = TestSessionPlugin('healthy');

        runtime.addPlugin(thrower);
        runtime.addPlugin(healthy);
        runtime.init();

        await expectLater(
          runtime.createSession(settings: RuntimeSettings()),
          throwsA(isA<PluginLifecycleException>()),
        );

        // The healthy plugin should still be attached despite thrower crashing
        expect(healthy.lifecycleCalls, contains('attach'));
      },
    );
  });

  group('Custom context type guards', () {
    test(
      'createSession without contextFactory throws when S is custom type',
      () async {
        final customRuntime =
            PluginRuntime<GlobalPluginContext, CustomSessionContext>.empty();
        customRuntime.init();

        expect(
          () => customRuntime.createSession(settings: RuntimeSettings()),
          throwsStateError,
        );

        await customRuntime.dispose();
      },
    );

    test('createSession with contextFactory works for custom type', () async {
      final customRuntime =
          PluginRuntime<GlobalPluginContext, CustomSessionContext>.empty();
      customRuntime.init();

      final session = await customRuntime.createSession(
        settings: RuntimeSettings(),
        contextFactory: (registry, sessionBus, globalBus) =>
            CustomSessionContext(
              registry: registry,
              bus: sessionBus,
              globalBus: globalBus,
              custom: 'hello',
            ),
      );

      expect(session.context.custom, 'hello');

      await customRuntime.dispose();
    });

    test('init without globalContextFactory throws when G is custom type', () {
      final customRuntime =
          PluginRuntime<CustomGlobalContext, SessionPluginContext>.empty();

      expect(() => customRuntime.init(), throwsStateError);
    });

    test('init with globalContextFactory works for custom type', () async {
      final customRuntime =
          PluginRuntime<CustomGlobalContext, SessionPluginContext>.empty();

      customRuntime.init(
        globalContextFactory: (registry, bus, sessions) => CustomGlobalContext(
          registry: registry,
          bus: bus,
          sessions: sessions,
          custom: 'world',
        ),
      );

      expect(customRuntime.globalContext.custom, 'world');

      await customRuntime.dispose();
    });
  });
}
