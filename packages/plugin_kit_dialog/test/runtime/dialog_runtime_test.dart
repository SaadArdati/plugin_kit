import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/advanced_tab_plugin.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/plugins_tab_plugin.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/services_tab_plugin.dart';

void main() {
  test('dialog runtime constructs and disposes cleanly', () async {
    final target = PluginRuntime();
    target.init(settings: RuntimeSettings());
    addTearDown(target.dispose);

    final controller = PluginKitDialogController(
      runtime: target,
      initialSettings: RuntimeSettings(),
    );

    final runtime =
        PluginRuntime<DialogGlobalContext, SessionPluginContext>(
          plugins: [
            PluginsTabPlugin(),
            FieldRenderersPlugin(),
            ServicesTabPlugin(),
            AdvancedTabPlugin(),
          ],
        )..init(
          globalContextFactory: (registry, bus, sessions) =>
              DialogGlobalContext(
                registry: registry,
                bus: bus,
                sessions: sessions,
                runtime: target,
                controller: controller,
                onSave: (_) {},
                onCancel: () {},
              ),
        );

    expect(runtime.globalContext, isA<DialogGlobalContext>());
    await runtime.dispose();
  });
}
