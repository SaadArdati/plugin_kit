import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('PluginContext', () {
    test('stub creates minimal context', () {
      final context = PluginContext.stub();
      expect(context.bus, isA<EventBus>());
      expect(context.registry, isA<ServiceRegistry>());
    });

    test('resolve delegates to registry', () {
      final registry = ServiceRegistry.empty();
      registry.registerSingleton<String>(
        pluginId: const PluginId('test'),
        serviceId: const ServiceId('greeting'),
        instance: 'hello',
      );
      final context = PluginContext(registry: registry, bus: EventBus());
      expect(context.resolve<String>(const ServiceId('greeting')), 'hello');
    });
  });

  group('GlobalPluginContext', () {
    test('bus is the global bus', () {
      final globalBus = EventBus();
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: globalBus,
      );
      expect(context.bus, same(globalBus));
    });

    test('sessions defaults to empty list', () {
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
      );
      expect(context.sessions, isEmpty);
    });

    test('sessions holds live reference', () {
      final sessionList = <PluginSession>[];
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        sessions: sessionList,
      );

      final session = _stubSession();
      sessionList.add(session);

      expect(context.sessions, hasLength(1));
      expect(context.sessions.first, same(session));
    });

    test('sessionOf finds session containing plugin', () {
      final session = _stubSession();
      session.markPluginEnabled(const PluginId('chat'));

      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        sessions: [session],
      );

      expect(context.sessionOf(const PluginId('chat')), same(session));
    });

    test('sessionOf throws when plugin not in any session', () {
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        sessions: [],
      );

      expect(
        () => context.sessionOf(const PluginId('nonexistent')),
        throwsStateError,
      );
    });

    test('copyWith preserves sessions', () {
      final sessions = <PluginSession>[];
      final original = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        sessions: sessions,
      );
      final copy = original.copyWith();
      expect(copy, isA<GlobalPluginContext>());
      expect(copy.sessions, same(sessions));
    });

    test('is a PluginContext', () {
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
      );
      expect(context, isA<PluginContext>());
    });
  });

  group('SessionPluginContext', () {
    test('bus is the session bus, globalBus is separate', () {
      final sessionBus = EventBus();
      final globalBus = EventBus();
      final context = SessionPluginContext(
        registry: ServiceRegistry.empty(),
        bus: sessionBus,
        globalBus: globalBus,
      );
      expect(context.bus, same(sessionBus));
      expect(context.globalBus, same(globalBus));
      expect(context.bus, isNot(same(context.globalBus)));
    });

    test('copyWith preserves globalBus', () {
      final globalBus = EventBus();
      final original = SessionPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        globalBus: globalBus,
      );
      final copy = original.copyWith();
      expect(copy, isA<SessionPluginContext>());
      expect(copy.globalBus, same(globalBus));
    });

    test('is a PluginContext', () {
      final context = SessionPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        globalBus: EventBus(),
      );
      expect(context, isA<PluginContext>());
    });
  });

  group('SessionBroadcast extension', () {
    test('emit broadcasts to all session buses', () async {
      final received1 = <String>[];
      final received2 = <String>[];

      final bus1 = EventBus();
      final bus2 = EventBus();

      bus1.on<String>((e) {
        received1.add(e.event);
      });
      bus2.on<String>((e) {
        received2.add(e.event);
      });

      final sessions = [
        PluginSession(
          registry: ServiceRegistry.empty(),
          bus: bus1,
          context: SessionPluginContext.stub(),
          plugins: [],
          settings: RuntimeSettings(),
        ),
        PluginSession(
          registry: ServiceRegistry.empty(),
          bus: bus2,
          context: SessionPluginContext.stub(),
          plugins: [],
          settings: RuntimeSettings(),
        ),
      ];

      await sessions.emit<String>('broadcast-event');
      expect(received1, ['broadcast-event']);
      expect(received2, ['broadcast-event']);
    });

    test('stopping in one session does not affect others', () async {
      final bus1 = EventBus();
      final bus2 = EventBus();
      var bus2Called = false;

      bus1.on<String>((e) async => e.stop('stopped'));
      bus2.on<String>((event) {
        bus2Called = true;
      });

      final sessions = [
        PluginSession(
          registry: ServiceRegistry.empty(),
          bus: bus1,
          context: SessionPluginContext.stub(),
          plugins: [],
          settings: RuntimeSettings(),
        ),
        PluginSession(
          registry: ServiceRegistry.empty(),
          bus: bus2,
          context: SessionPluginContext.stub(),
          plugins: [],
          settings: RuntimeSettings(),
        ),
      ];

      await sessions.emit<String>('test');
      expect(bus2Called, isTrue);
    });

    test('emit on empty sessions list is a no-op', () async {
      final sessions = <PluginSession>[];
      await expectLater(sessions.emit<String>('test'), completes);
    });
  });
}

/// Minimal [PluginSession] stub for `GlobalPluginContext` tests that need
/// a session instance but not a real runtime.
PluginSession _stubSession() {
  final bus = EventBus();
  return PluginSession(
    registry: ServiceRegistry.empty(),
    bus: bus,
    context: SessionPluginContext(
      registry: ServiceRegistry.empty(),
      bus: bus,
      globalBus: EventBus(),
    ),
    plugins: const [],
    settings: RuntimeSettings(),
  );
}
