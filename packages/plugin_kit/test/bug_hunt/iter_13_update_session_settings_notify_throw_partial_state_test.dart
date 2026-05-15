import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ThrowOnSettingsChangedPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('throw_on_settings_changed');

  @override
  Future<void> onPluginSettingsChanged(
    SessionPluginContext oldContext,
    SessionPluginContext newContext,
  ) async {
    throw StateError('settings changed hook failed');
  }
}

void main() {
  group(
    'bug-hunt iter 13: update-session-settings-notify-throw-partial-state',
    () {
      test('keeps plugin disabled when settings-change notification throws',
          () async {
        const pluginId = PluginId('throw_on_settings_changed');
        const disabled = RuntimeSettings(
          plugins: {pluginId: PluginConfig(enabled: false)},
        );
        final runtime = PluginRuntime(plugins: [_ThrowOnSettingsChangedPlugin()])
          ..init(settings: disabled);
        addTearDown(runtime.dispose);
        final session = await runtime.createSession(settings: disabled);

        await expectLater(
          () => runtime.updateSessionSettings(
            session,
            newSettings: const RuntimeSettings(
              plugins: {pluginId: PluginConfig(enabled: true)},
            ),
          ),
          throwsA(isA<StateError>()),
        );

        expect(session.isPluginEnabled(pluginId), isFalse);
      });
    },
  );
}
