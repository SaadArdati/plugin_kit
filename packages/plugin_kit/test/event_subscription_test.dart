// Verifies that `EventBus.on` / `onSync` / `onRequest` / `onRequestSync`
// return a typed `EventSubscription` (cancel-only handle), not a
// `StreamSubscription`. The previous `_EventHandlerSub` implemented
// `StreamSubscription` but threw `UnsupportedError` on every non-cancel
// method, which made the returned value fragile when fed into
// stream-aware utilities.
//
// `EventBinding` keeps its existing role (a declarative descriptor with
// `attachTo(session)`); `EventSubscription` is the live cancellation
// token returned at attach time.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('EventSubscription return type', () {
    test('on() returns an EventSubscription whose cancel() actually cancels',
        () async {
      final bus = EventBus();
      var count = 0;

      // Type assertion is the load-bearing line: this assignment must
      // compile, which forces `on` to return EventSubscription.
      final EventSubscription sub = bus.on<int>((env) => count++);

      await bus.emit<int>(event: 1);
      expect(count, 1);

      await sub.cancel();
      await bus.emit<int>(event: 2);
      expect(count, 1, reason: 'handler must not fire after cancel()');
    });

    test('onSync() returns an EventSubscription', () async {
      final bus = EventBus();
      final EventSubscription sub = bus.onSync<int>((env) {});
      await sub.cancel();
    });

    test('onRequest() returns an EventSubscription', () async {
      final bus = EventBus();
      final EventSubscription sub =
          bus.onRequest<int, String>((env) async => 'ok');
      expect(await bus.request<int, String>(1), 'ok');
      await sub.cancel();
    });

    test('onRequestSync() returns an EventSubscription', () async {
      final bus = EventBus();
      final EventSubscription sub =
          bus.onRequestSync<int, String>((env) => 'ok');
      expect(bus.requestSync<int, String>(1), 'ok');
      await sub.cancel();
    });

    test(
      'Plugin and StatefulPluginService helpers also return '
      'EventSubscription',
      () async {
        final pluginCtx = SessionPluginContext.stub();
        final plugin = _StubPlugin();
        final EventSubscription pluginSub =
            plugin.on<int>(pluginCtx, (env) {});
        await pluginSub.cancel();

        final service = _StubStatefulService();
        // `attach()` runs through the framework normally; for this test
        // we just need a service with a bound context to exercise the
        // helper return type. Hand-bind via plugin lifecycle on a fresh
        // runtime so `this.context` is available.
        final runtime = PluginRuntime(plugins: [_HostingPlugin(service)])
          ..init();
        final session = await runtime.createSession();
        session.resolve<_StubStatefulService>(const ServiceId('stub'));

        final EventSubscription serviceSub = service.on<int>((env) {});
        await serviceSub.cancel();

        await runtime.dispose();
      },
    );
  });
}

class _StubPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('stub_plugin');
}

class _StubStatefulService
    extends StatefulPluginService<SessionPluginContext> {}

class _HostingPlugin extends SessionPlugin {
  _HostingPlugin(this._service);
  final _StubStatefulService _service;

  @override
  PluginId get pluginId => const PluginId('host');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_StubStatefulService>(
      const ServiceId('stub'),
      () => _service,
    );
  }
}
