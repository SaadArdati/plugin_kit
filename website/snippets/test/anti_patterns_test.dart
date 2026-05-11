import 'package:docs_snippets/anti_patterns.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('anti-pattern-direct-subscribe-wrong', () {
    test('MyRedactionPluginWrong has correct plugin id', () {
      expect(
        MyRedactionPluginWrong().pluginId,
        equals(const PluginId('my_redaction_wrong')),
      );
    });
  });

  group('anti-pattern-direct-subscribe-fix', () {
    test('MyRedactionPlugin registers Redactor service', () async {
      final runtime = PluginRuntime(plugins: [MyRedactionPlugin()])..init();
      final session = await runtime.createSession();
      final redactor = session.maybeResolve<Redactor>(const ServiceId('redactor'));
      expect(redactor, isNotNull);
      expect(redactor!.redact('keep secret safe'), contains('[REDACTED]'));
      await runtime.dispose();
    });
  });

  group('anti-pattern-string-settings-key-fix', () {
    test('correctSettings uses typed Pins', () {
      expect(correctSettings.services, hasLength(2));
      for (final pin in correctSettings.services.keys) {
        expect(pin.wire, isA<String>());
      }
    });
  });

  group('anti-pattern-resolve-in-register-fix', () {
    test('GoodPlugin attaches without error', () async {
      final loggerPlugin = SessionPlugin2();
      final runtime = PluginRuntime(
        plugins: [loggerPlugin, GoodPlugin()],
      )..init();
      final session = await runtime.createSession();
      expect(session, isNotNull);
      await runtime.dispose();
    });
  });

  group('anti-pattern-cache-resolution-fix', () {
    test('NonCachingService is constructable', () {
      final svc = NonCachingService();
      expect(svc, isNotNull);
    });
  });

  group('anti-pattern-shared-instance-fix', () {
    test('isolated plugin plugin id is correct', () {
      expect(SessionPlugin2().pluginId, equals(const PluginId('isolated_plugin')));
    });
  });
}
