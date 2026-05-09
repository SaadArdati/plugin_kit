import 'package:flutter/material.dart';

import '../../controller/plugin_kit_dialog_controller.dart';
import '../../theme/plugin_kit_dialog_theme.dart';
import '../shared/compact_switch.dart';
import '../shared/plugin_kit_dialog_card.dart';

/// Card that exposes output-related toggles for advanced dialog behavior.
class OutputOptionsCard extends StatelessWidget {
  /// Dialog controller associated with the host dialog.
  final PluginKitDialogController controller;

  /// Creates an output options card.
  const OutputOptionsCard({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = PluginKitDialogTheme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return PluginKitDialogCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              CompactSwitch(
                value: controller.showAllServices,
                onChanged: (value) => controller.showAllServices = value,
              ),
              const SizedBox(width: 12),
              Icon(Icons.tune, size: 16, color: theme.agentAccent),
              const SizedBox(width: 8),
              Text(
                'Show all services',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'When enabled, displays defaults alongside overrides in the '
                  'JSON preview below.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
