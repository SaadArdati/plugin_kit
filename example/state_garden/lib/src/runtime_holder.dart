import 'package:plugin_kit/plugin_kit.dart';

import 'chat/chat_plugin.dart';

/// Owns the [PluginRuntime] and an initial [PluginSession] for tests
/// and the example app.
///
/// Use [create] to build a ready-to-use holder. The caller owns disposal:
/// invoke [dispose] in widget teardown or test `addTearDown`. Only the
/// runtime is disposed; per the runtime contract the runtime iterates and
/// disposes live sessions itself, so calling `session.dispose()` separately
/// would race on stateful service detach.
class RuntimeHolder {
  RuntimeHolder._(this.runtime, this.session);

  final PluginRuntime runtime;
  final PluginSession session;

  static Future<RuntimeHolder> create() async {
    final runtime = PluginRuntime(plugins: <Plugin>[ChatPlugin()])..init();
    final session = await runtime.createSession();
    return RuntimeHolder._(runtime, session);
  }

  Future<void> dispose() => runtime.dispose();
}
