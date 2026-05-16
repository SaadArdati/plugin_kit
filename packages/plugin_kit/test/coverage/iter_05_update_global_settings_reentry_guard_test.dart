import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _NoopGlobalPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('noop_global');
}

void main() {
  test(
    'updateGlobalSettings throws StateError naming the entrypoint while settings reconciliation is already in progress',
    () async {
      final runtime = PluginRuntime(plugins: [_NoopGlobalPlugin()])..init();

      final first = runtime.updateSettings(
        const RuntimeSettings(
          plugins: {PluginId('noop_global'): PluginConfig(enabled: false)},
        ),
      );

      await expectLater(
        () => runtime.updateGlobalSettings(
          oldSettings: runtime.settings,
          newSettings: const RuntimeSettings(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('PluginRuntime.updateGlobalSettings'),
              contains('already in progress'),
            ),
          ),
        ),
      );

      await expectLater(first, completes);
      await runtime.dispose();
    },
  );
}
