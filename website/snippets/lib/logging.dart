/// Snippets for PluginLifecycleException handling and log discipline.
library;

import 'package:logging/logging.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// A plugin that crashes during attach, used in exception examples.
class CrashingPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('crashing_plugin');

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('intentional crash for demo');
  }
}

// #docregion logging-logger-listen
/// Wires the root `plugin_kit` logger to print every record.
void listenToPluginKitLogger() {
  Logger('plugin_kit').onRecord.listen((record) {
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
  });
}
// #enddocregion logging-logger-listen

// #docregion logging-lifecycle-exception
Future<void> handleLifecycleException() async {
  final runtime = PluginRuntime(plugins: [CrashingPlugin()]);

  try {
    runtime.init();
  } on PluginLifecycleException catch (e) {
    print('Phase: ${e.phase}');
    for (final (pluginId, error, _) in e.failures) {
      print('  $pluginId failed: $error');
    }
  }
}
// #enddocregion logging-lifecycle-exception

// #docregion logging-request-unavailable
Future<void> handleRequestUnavailable(PluginContext context) async {
  try {
    await context.bus.request<String, int>('query');
  } on RequestUnavailableException catch (e) {
    print('No handler for ${e.requestType} -> ${e.responseType}: ${e.reason}');
  }
}
// #enddocregion logging-request-unavailable

// #docregion logging-try-catch-plugin-init
Future<void> safeInit() async {
  final runtime = PluginRuntime();

  try {
    runtime.init();
  } on PluginLifecycleException catch (e) {
    print('attach failed: ${e.phase}');
    // Inspect e.failures for per-plugin error details.
    rethrow;
  }
}
// #enddocregion logging-try-catch-plugin-init

// #docregion logging-fine-level
/// Raises specific plugin_kit loggers to FINE for diagnostic output.
void setFineLogging() {
  Logger('plugin_kit.PluginRuntime').level = Level.FINE;
  Logger('plugin_kit.PluginSession').level = Level.FINE;
}
// #enddocregion logging-fine-level
