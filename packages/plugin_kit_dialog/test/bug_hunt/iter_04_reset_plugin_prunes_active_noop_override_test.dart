import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

void main() {
  group('bug-hunt iter 4: reset-plugin-prunes-active-noop-override', () {
    test('resetPlugin restores active override and clears dirty state', () {
      const pluginId = PluginId('auto_retry');
      final controller = PluginKitDialogController(
        runtime: PluginRuntime(plugins: [_StablePlugin(pluginId)]),
        initialSettings: const RuntimeSettings(
          plugins: {pluginId: PluginConfig(enabled: true)},
        ),
      );

      controller.setPluginEnabled(pluginId, false);
      controller.resetPlugin(pluginId);

      expect(controller.isDirty, isFalse);
    });
  });
}

class _StablePlugin extends GlobalPlugin {
  _StablePlugin(this._pluginId);

  final PluginId _pluginId;

  @override
  PluginId get pluginId => _pluginId;
}
