import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../controller/plugin_kit_dialog_controller.dart';
import '../../theme/plugin_kit_dialog_tokens.dart';
import '../advanced/json_preview_editor.dart';
import '../advanced/output_options_card.dart';
import '../advanced/service_registry_inspector.dart';

/// Advanced tab body that renders registry tools and JSON preview controls.
class AdvancedTab extends StatelessWidget {
  /// Controller backing the dialog draft and JSON preview.
  final PluginKitDialogController controller;

  /// Runtime being edited by this dialog.
  final PluginRuntime runtime;

  /// Creates an advanced tab bound to [controller] and [runtime].
  const AdvancedTab({
    required this.controller,
    required this.runtime,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sectionGap = kSectionGap.top;

    return SingleChildScrollView(
      padding: kCardPadding,
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          ServiceRegistryInspector(runtime: runtime, controller: controller),
          SizedBox(height: sectionGap),
          OutputOptionsCard(controller: controller),
          SizedBox(height: sectionGap),
          JsonPreviewEditor(controller: controller),
        ],
      ),
    );
  }
}
