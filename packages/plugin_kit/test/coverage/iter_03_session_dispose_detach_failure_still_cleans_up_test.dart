import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ThrowingDetachPlugin extends SessionPlugin<SessionPluginContext> {
  @override
  PluginId get pluginId => const PluginId('throwing_detach');

  @override
  Future<void> detach(SessionPluginContext context) async {
    throw StateError('detach failed');
  }
}

void main() {
  test(
    'dispose detaches with failure but still disposes bus and removes session from runtime tracking',
    () async {
      final runtime = PluginRuntime<GlobalPluginContext, SessionPluginContext>(
        plugins: [_ThrowingDetachPlugin()],
      )..init();
      addTearDown(runtime.dispose);

      final session = await runtime.createSession();
      expect(runtime.sessions, contains(session));
      expect(runtime.globalContext.sessions, contains(session));

      await expectLater(
        session.dispose(),
        throwsA(isA<PluginLifecycleException>()),
      );

      expect(session.bus.isDisposed, isTrue);
      expect(runtime.sessions, isNot(contains(session)));
      expect(runtime.globalContext.sessions, isNot(contains(session)));
    },
  );
}
