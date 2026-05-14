/// Snippets for PluginLifecycleException handling and log discipline.
library;

import 'package:flutter/widgets.dart';
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

/// Stand-in for the host application's root widget. The README's
/// `runApp(MyApp())` line resolves to this stub when the snippet is
/// compiled, which is all that matters for validation; readers
/// substitute their own widget.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// #docregion logging-logger-listen
/// Wires the root `plugin_kit` logger to print every record.
void listenToPluginKitLogger() {
  Logger('plugin_kit').onRecord.listen((record) {
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
  });
}
// #enddocregion logging-logger-listen

// #docregion logging-root-listen-main
void main() {
  Logger.root.level = Level.INFO; // or Level.ALL during development
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
    if (record.error != null) print('  ${record.error}');
    if (record.stackTrace != null) print(record.stackTrace);
  });

  runApp(const MyApp());
}
// #enddocregion logging-root-listen-main

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
  } on RequestNotWiredException catch (e) {
    // Almost always a wiring bug: register a handler with onRequest.
    print('No handler for ${e.requestType} -> ${e.responseType}');
  } on AllConcededException catch (e) {
    // Every handler ran and returned null. If concession is legitimate
    // at this call site, prefer maybeRequest instead of request.
    print('All handlers conceded for ${e.requestType}: ${e.suggestion}');
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
