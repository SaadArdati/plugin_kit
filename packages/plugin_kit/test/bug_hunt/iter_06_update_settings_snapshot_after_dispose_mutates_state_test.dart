import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group(
    'bug-hunt iter 6: update-settings-snapshot-after-dispose-mutates-state',
    () {
      test(
        'rejects updateSettingsSnapshot after dispose without changing stored settings',
        () async {
          final runtime = PluginRuntime()..init();
          final beforeDispose = runtime.settings;
          await runtime.dispose();

          final newSnapshot = RuntimeSettings(
            plugins: {
              const PluginId('plugin_after_dispose'): const PluginConfig(
                enabled: false,
              ),
            },
          );

          expect(
            () => runtime.updateSettingsSnapshot(newSnapshot),
            throwsA(isA<StateError>()),
          );
          expect(runtime.settings, equals(beforeDispose));
        },
      );
    },
  );
}
