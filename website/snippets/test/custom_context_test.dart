import 'package:docs_snippets/custom_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('session-plugin-context-subclass', () {
    test('EditorSessionContext holds document and user', () {
      final ctx = EditorSessionContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        globalBus: EventBus(),
        document: const Document(title: 'readme.md'),
        user: const UserSession(id: 'user-1'),
      );
      expect(ctx.document.title, equals('readme.md'));
      expect(ctx.user.id, equals('user-1'));
    });
  });

  group('session-plugin-typed-context', () {
    test('AutosavePlugin has correct pluginId', () {
      final plugin = AutosavePlugin();
      expect(plugin.pluginId, equals(const PluginId('autosave')));
    });
  });

  group('global-plugin-context-subclass', () {
    test('EditorGlobalContext holds application and flags', () {
      final ctx = EditorGlobalContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        sessions: const [],
        application: EditorApplication(),
        flags: FeatureFlagClient(),
      );
      expect(ctx.application, isNotNull);
      expect(ctx.flags.isOn('nonexistent'), isFalse);
    });
  });

  group('global-plugin-typed-context', () {
    test('AnalyticsPlugin has correct pluginId', () {
      expect(AnalyticsPlugin().pluginId, equals(const PluginId('analytics')));
    });
  });

  group('plugin-context-stub', () {
    test('stub context is valid', () {
      final ctx = makeTestContext();
      expect(ctx, isNotNull);
      expect(ctx.registry, isNotNull);
    });
  });

  group('session-plugin-context-stub', () {
    test('session context stub is valid', () {
      final ctx = makeTestSessionContext();
      expect(ctx, isNotNull);
      expect(ctx.globalBus, isNotNull);
    });
  });

  group('global-plugin-context-stub', () {
    test('global context stub is valid', () {
      final ctx = makeTestGlobalContext();
      expect(ctx, isNotNull);
      expect(ctx.sessions, isEmpty);
    });
  });
}
