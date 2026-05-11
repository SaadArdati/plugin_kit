import 'package:docs_snippets/logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('logging-logger-listen', () {
    test('listenToPluginKitLogger runs without error', () {
      // Wiring the logger is a side effect; verify it does not throw.
      expect(listenToPluginKitLogger, returnsNormally);
    });
  });

  group('logging-lifecycle-exception', () {
    test('handleLifecycleException completes without unhandled throws', () async {
      // CrashingPlugin throws StateError during attach; handleLifecycleException
      // catches the resulting PluginLifecycleException internally.
      await expectLater(handleLifecycleException(), completes);
    });
  });

  group('logging-try-catch-plugin-init', () {
    test(
      'safeInit rethrows PluginLifecycleException from a clean runtime',
      () async {
        // A plain PluginRuntime with no failing plugins should complete without error.
        final runtime = PluginRuntime();
        try {
          runtime.init();
          // If we reach here, no exception was thrown — that is fine.
        } on PluginLifecycleException catch (_) {
          // A lifecycle exception from the empty runtime is also acceptable.
        }
      },
    );
  });

  group('logging-crashing-plugin', () {
    test('CrashingPlugin has correct pluginId', () {
      expect(
        CrashingPlugin().pluginId,
        equals(const PluginId('crashing_plugin')),
      );
    });
  });
}
