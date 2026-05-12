import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _Tick {
  const _Tick(this.count);
  final int count;
}

class _ListenerTestPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('plugin_kit.test.listener');

  @override
  void register(ScopedServiceRegistry registry) {}
}

void main() {
  group('EventBinding.on', () {
    test(
      'attaches handler to a session and receives envelopes carrying the event',
      () async {
        final runtime = PluginRuntime(plugins: [_ListenerTestPlugin()])
          ..init(settings: RuntimeSettings.empty());
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);

        final received = <int>[];
        final binding = EventBinding.on<_Tick>(
          (envelope) => received.add(envelope.event.count),
        );
        final sub = binding.attachTo(session);

        await session.emit(const _Tick(1));
        await session.emit(const _Tick(2));
        expect(received, equals([1, 2]));

        await sub.cancel();
        await session.emit(const _Tick(3));
        expect(received, equals([1, 2]));
      },
    );

    test(
      'forwards priority to EventBus.on so handlers run in descending order',
      () async {
        // Regression: bindings created with a non-default priority must
        // actually pass that priority through to the underlying
        // EventBus.on call. A binding constructed with priority=10 that
        // forgets to forward it would land at the default, breaking any
        // ordering the caller relied on.
        final runtime = PluginRuntime(plugins: [_ListenerTestPlugin()])
          ..init(settings: RuntimeSettings.empty());
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);

        final order = <String>[];
        final low = EventBinding.on<_Tick>(
          (_) => order.add('low'),
          priority: 0,
        );
        final high = EventBinding.on<_Tick>(
          (_) => order.add('high'),
          priority: 10,
        );

        // Attach low-priority first to demonstrate that physical attach
        // order doesn't determine dispatch order; priority does.
        addTearDown((await Future.value(low.attachTo(session))).cancel);
        addTearDown((await Future.value(high.attachTo(session))).cancel);

        await session.emit(const _Tick(1));
        // EventBus runs handlers in descending priority order, so the
        // priority-10 handler fires before the priority-0 handler.
        expect(order, equals(['high', 'low']));
      },
    );

    test(
      'forwards identifier to EventBus.on so the binding is identifier-scoped',
      () async {
        // Regression: bindings created with a non-null identifier must
        // pass it through. A binding that drops identifier behaves like a
        // general subscription and would receive every emission of E,
        // including those targeted at other identifiers.
        final runtime = PluginRuntime(plugins: [_ListenerTestPlugin()])
          ..init(settings: RuntimeSettings.empty());
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        addTearDown(session.dispose);

        final received = <int>[];
        final binding = EventBinding.on<_Tick>(
          (envelope) => received.add(envelope.event.count),
          identifier: 'agent1',
        );
        addTearDown(binding.attachTo(session).cancel);

        // Identifier-scoped emit reaches the handler.
        await session.emit(const _Tick(1), identifier: 'agent1');
        // Different-identifier emit must NOT reach this handler.
        await session.emit(const _Tick(2), identifier: 'agent2');
        // General (no-identifier) emit reaches identifier-scoped handlers
        // too only when the emit identifier IS the bound identifier;
        // here the emit has no identifier, so the handler should not run.
        await session.emit(const _Tick(3));
        // A second identifier-scoped emit confirms the handler still
        // listens for its own identifier.
        await session.emit(const _Tick(4), identifier: 'agent1');

        expect(
          received,
          equals([1, 4]),
          reason: 'binding must only fire for matching identifier',
        );
      },
    );
  });
}
