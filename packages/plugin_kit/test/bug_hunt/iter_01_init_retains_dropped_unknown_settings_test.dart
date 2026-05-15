import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _AlphaPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');
}

void main() {
  group('bug-hunt iter 1: init-retains-dropped-unknown-settings', () {
    test('removes unknown plugin settings entries after init under logAndSkip', () {
      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      addTearDown(runtime.dispose);

      runtime.init(
        unknownReferencePolicy: UnknownReferencePolicy.logAndSkip,
        settings: const RuntimeSettings(
          plugins: {
            PluginId('alpha'): PluginConfig(enabled: false),
            PluginId('unknown_plugin'): PluginConfig(enabled: true),
          },
        ),
      );

      expect(
        runtime.settings.plugins.containsKey(const PluginId('unknown_plugin')),
        isFalse,
      );
    });
  });
}
