import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('PluginLifecycleException', () {
    test('stores phase and failures', () {
      final exception = PluginLifecycleException('attachGlobal', [
        (const PluginId('pluginA'), Exception('boom'), StackTrace.current),
        (
          const PluginId('pluginB'),
          StateError('bad state'),
          StackTrace.current,
        ),
      ]);

      expect(exception.phase, 'attachGlobal');
      expect(exception.failures, hasLength(2));
      expect(exception.failures[0].$1, const PluginId('pluginA'));
      expect(exception.failures[1].$1, const PluginId('pluginB'));
    });

    test('implements Exception', () {
      final exception = PluginLifecycleException('attach', []);
      expect(exception, isA<Exception>());
    });

    test('toString includes phase and all plugin failures', () {
      final exception = PluginLifecycleException('attachGlobal', [
        (const PluginId('pluginA'), Exception('boom'), StackTrace.current),
        (
          const PluginId('pluginB'),
          StateError('Bad state: bad state'),
          StackTrace.current,
        ),
      ]);

      final str = exception.toString();
      expect(str, contains('attachGlobal'));
      expect(str, contains('pluginA'));
      expect(str, contains('pluginB'));
      expect(str, contains('boom'));
      expect(str, contains('bad state'));
    });

    test('failures list is unmodifiable', () {
      final exception = PluginLifecycleException('attach', [
        (const PluginId('pluginA'), Exception('boom'), StackTrace.current),
      ]);
      expect(
        () => exception.failures.add((
          const PluginId('x'),
          Error(),
          StackTrace.current,
        )),
        throwsUnsupportedError,
      );
    });

    test('toString with single failure', () {
      final exception = PluginLifecycleException('detachSession', [
        (
          const PluginId('myPlugin'),
          FormatException('oops'),
          StackTrace.current,
        ),
      ]);

      final str = exception.toString();
      expect(str, contains('detachSession'));
      expect(str, contains('myPlugin'));
      expect(str, contains('oops'));
    });
  });
}
