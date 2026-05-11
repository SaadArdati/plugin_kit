import 'package:docs_snippets/sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('theme-service-broadcast', () {
    test('ThemePlugin and ThemeAwarePlugin have correct ids', () {
      expect(ThemePlugin().pluginId, equals(const PluginId('theme')));
      expect(
        ThemeAwarePlugin().pluginId,
        equals(const PluginId('theme_aware')),
      );
    });
  });

  group('create-session-with-factory', () {
    test('session extras contain session_id', () async {
      final runtime = PluginRuntime.empty()..init();
      final session = await runtime.createSession(
        contextFactory: (registry, sessionBus, globalBus) =>
            SessionPluginContext(
              registry: registry,
              bus: sessionBus,
              globalBus: globalBus,
              extras: const {'session_id': 'chat-42'},
            ),
      );
      expect(session.context.extras['session_id'], equals('chat-42'));
      await runtime.dispose();
    });
  });

  group('multi-session-isolation', () {
    test('session buses are isolated', () async {
      final runtime = PluginRuntime.empty()..init();
      await demonstrateMultiSessionIsolation(runtime);
      await runtime.dispose();
    });
  });
}
