import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ExpA extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('a');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.experimental];
}

class _ThrowDetachB extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('b');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.experimental];

  @override
  Future<void> detach(SessionPluginContext context) async {
    throw StateError('detach failed');
  }
}

void main() {
  group('bug-hunt iter 3: update-settings-rollback-loses-custom-session-settings', () {
    test('restores each session to its own pre-update settings after rollback', () async {
      final runtime = PluginRuntime(plugins: [_ExpA(), _ThrowDetachB()])..init();
      // Dispose will throw because `_ThrowDetachB.detach` is by-design
      // throwing; that is orthogonal to what this test asserts (per-session
      // rollback). Swallow the dispose throw in teardown so the test
      // framework does not double-report.
      addTearDown(() async {
        try {
          await runtime.dispose();
        } catch (_) {}
      });

      final sessionA = await runtime.createSession(
        settings: const RuntimeSettings(
          plugins: {PluginId('a'): PluginConfig(enabled: true)},
        ),
      );
      await runtime.createSession(
        settings: const RuntimeSettings(
          plugins: {PluginId('b'): PluginConfig(enabled: true)},
        ),
      );

      await expectLater(
        runtime.updateSettings(const RuntimeSettings()),
        throwsA(isA<PluginLifecycleException>()),
      );

      expect(sessionA.isPluginEnabled(const PluginId('a')), isTrue);
    });
  });
}
