@Skip('ISSUE-20260515-1438-update-settings-logandskip-retains-unknown-plugin-config: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')
library;

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _AlphaPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');
}

void main() {
  group(
    'bug-hunt iter 12: update-settings-logandskip-retains-unknown-plugin-config',
    () {
      test(
        'drops unknown plugin ids from runtime settings after updateSettings under logAndSkip',
        () async {
          final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
          addTearDown(runtime.dispose);

          runtime.init(unknownReferencePolicy: UnknownReferencePolicy.logAndSkip);

          await runtime.updateSettings(
            const RuntimeSettings(
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
        },
      );
    },
  );
}
