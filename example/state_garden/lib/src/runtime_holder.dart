import 'package:plugin_kit/plugin_kit.dart';

import 'chat/chat_plugin.dart';

/// Owns the [PluginRuntimeManager] and an initial [PluginSession] for tests
/// and the example app.
///
/// Use [create] to build a ready-to-use holder. The caller owns disposal:
/// invoke [dispose] in widget teardown or test `addTearDown`. Only the
/// manager is disposed; per the runtime contract the manager iterates and
/// disposes live sessions itself, so calling `session.dispose()` separately
/// would race on stateful service detach.
class RuntimeHolder {
  RuntimeHolder._(this.manager, this.session);

  final PluginRuntimeManager manager;
  final PluginSession session;

  static Future<RuntimeHolder> create() async {
    final manager = PluginRuntimeManager(plugins: <Plugin>[ChatPlugin()])
      ..init();
    final session = await manager.createSession();
    return RuntimeHolder._(manager, session);
  }

  Future<void> dispose() => manager.dispose();
}
