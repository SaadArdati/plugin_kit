@Skip('ISSUE-20260515-1438-update-session-settings-accepts-foreign-session: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')
library;

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _SharedSessionPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('shared_session_plugin');
}

void main() {
  group('bug-hunt iter 8: update-session-settings-accepts-foreign-session', () {
    test('rejects updateSessionSettings for a session owned by another runtime',
        () async {
      final runtimeA = PluginRuntime(plugins: [_SharedSessionPlugin()])..init();
      final runtimeB = PluginRuntime(plugins: [_SharedSessionPlugin()])..init();
      addTearDown(runtimeA.dispose);
      addTearDown(runtimeB.dispose);

      final sessionA = await runtimeA.createSession();

      await expectLater(
        () => runtimeB.updateSessionSettings(
          sessionA,
          newSettings: const RuntimeSettings(
            plugins: {
              PluginId('shared_session_plugin'): PluginConfig(enabled: false),
            },
          ),
        ),
        throwsA(anything),
      );

      expect(sessionA.isPluginEnabled(const PluginId('shared_session_plugin')),
          isTrue);
    });
  });
}
