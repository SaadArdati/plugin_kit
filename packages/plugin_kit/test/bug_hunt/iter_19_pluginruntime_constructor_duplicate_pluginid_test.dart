import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _NoopGlobalPlugin extends GlobalPlugin {
  _NoopGlobalPlugin(String id) : pluginId = PluginId(id);
  @override
  final PluginId pluginId;
}

void main() {
  group('bug-hunt iter 19: pluginruntime-constructor-duplicate-pluginid', () {
    test('rejects duplicate pluginIds at construction with ArgumentError', () {
      expect(
        () => PluginRuntime(
          plugins: [_NoopGlobalPlugin('dup'), _NoopGlobalPlugin('dup')],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('duplicate pluginId'), contains('"dup"')),
          ),
        ),
      );
    });

    test('accepts distinct pluginIds at construction', () {
      final runtime = PluginRuntime(
        plugins: [_NoopGlobalPlugin('a'), _NoopGlobalPlugin('b')],
      );
      expect(runtime.plugins.length, 2);
    });
  });
}
