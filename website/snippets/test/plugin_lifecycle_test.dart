import 'package:docs_snippets/plugin_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('session-plugin-basic', () {
    test('formal plugin wins with higher priority', () async {
      final runtime = PluginRuntime(plugins: [CasualPlugin(), FormalPlugin()])
        ..init();
      final session = await runtime.createSession();

      final greeter = session.resolve<Greeter>(const ServiceId('greeter'));
      expect(greeter.greet('world'), equals('Good day, world.'));

      await runtime.dispose();
    });
  });

  group('feature-flag', () {
    test('experimental plugin is disabled by default', () {
      final runtime = PluginRuntime(plugins: [ExperimentalPlugin()])..init();
      expect(
        runtime.isPluginEnabled(const PluginId('experimental_feature')),
        isFalse,
      );
    });
  });

  group('locked-plugin', () {
    test('locked plugin cannot be disabled', () {
      final runtime = PluginRuntime(plugins: [CorePlugin()])
        ..init(
          settings: const RuntimeSettings(
            plugins: {PluginId('core'): PluginConfig(enabled: false)},
          ),
        );
      expect(runtime.isPluginEnabled(const PluginId('core')), isTrue);
    });
  });

  group('plugin-dependencies', () {
    test('analytics plugin declares core as dependency', () {
      final plugin = AnalyticsPlugin();
      expect(plugin.dependencies, contains(const PluginId('core')));
    });
  });

  group('session-plugin-attach', () {
    test('greeter plugin registers service', () async {
      final runtime = PluginRuntime(plugins: [GreeterPlugin()])..init();
      final session = await runtime.createSession();
      final svc = session.resolve<GreeterService>(
        const ServiceId('greeter_service'),
      );
      expect(svc, isNotNull);
      await runtime.dispose();
    });
  });

  group('runtime-update-snapshot', () {
    test('demonstrateUpdateModes completes without error', () async {
      // The snippet toggles `analytics` off, which requires that plugin
      // to be registered on the runtime (the runtime now rejects
      // settings entries for unknown plugin ids).
      final runtime = PluginRuntime(
        plugins: [CasualPlugin(), CorePlugin(), AnalyticsPlugin()],
      )..init();
      await expectLater(demonstrateUpdateModes(runtime), completes);
      await runtime.dispose();
    });
  });

  group('runtime-update-settings', () {
    test('disabling analytics removes it', () async {
      final runtime = PluginRuntime(plugins: [CasualPlugin()])..init();
      expect(runtime.isPluginEnabled(const PluginId('casual')), isTrue);
      await runtime.updateSettings(
        const RuntimeSettings(
          plugins: {PluginId('casual'): PluginConfig(enabled: false)},
        ),
      );
      expect(runtime.isPluginEnabled(const PluginId('casual')), isFalse);
      await runtime.dispose();
    });
  });

  group('plugin-id-value-equality', () {
    test('PluginId.value returns the wrapped string', () {
      const id = PluginId('greeter');
      expect(id.value, equals('greeter'));
      expect(id == const PluginId('greeter'), isTrue);
    });
  });

  group('sessions-broadcast-invalidate-cache', () {
    test('broadcastInvalidateCache reaches session handlers', () async {
      final runtime = PluginRuntime()..init();
      final session = await runtime.createSession();

      var received = false;
      session.on<InvalidateCacheEvent>((_) {
        received = true;
      });

      await broadcastInvalidateCache(runtime.globalContext);
      expect(received, isTrue);
      await runtime.dispose();
    });
  });
}
