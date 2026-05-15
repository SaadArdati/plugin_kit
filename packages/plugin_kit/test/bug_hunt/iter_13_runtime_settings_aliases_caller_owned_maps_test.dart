@Skip('ISSUE-runtime-settings-aliases-caller-owned-maps: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')
library;

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _SessionProbePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('session_probe');
}

void main() {
  group('bug-hunt iter 13: runtime-settings-aliases-caller-owned-maps', () {
    test(
      'createSession uses init-time settings snapshot when caller mutates original settings map later',
      () async {
        final plugin = _SessionProbePlugin();
        final mutablePlugins = <PluginId, PluginConfig>{};
        final settings = RuntimeSettings(plugins: mutablePlugins);

        final runtime = PluginRuntime(plugins: [plugin])
          ..init(settings: settings);
        addTearDown(runtime.dispose);

        mutablePlugins[plugin.pluginId] = const PluginConfig(enabled: false);

        final session = await runtime.createSession();

        expect(session.isPluginEnabled(plugin.pluginId), isTrue);
      },
    );
  });
}
