import 'package:flutter/material.dart';

import '../../../plugin_kit_dialog.dart';
import '../../theme/plugin_kit_dialog_theme.dart';
import '../../theme/plugin_kit_dialog_tokens.dart';
import '../shared/section_header.dart';
import 'plugin_card.dart';

/// Section that renders a titled group of plugin chips.
class PluginSection extends StatelessWidget {
  /// Controller used to read and mutate plugin enablement in the draft.
  final PluginKitDialogController controller;

  /// Resolved plugin rows shown as chips in this section.
  final List<PluginChipModel> plugins;

  /// Section title shown in the header.
  final String title;

  /// Section subtitle shown under [title].
  final String subtitle;

  /// Leading header icon.
  final IconData icon;

  /// Accent used by the section header chrome.
  final Color accent;

  /// Creates a plugin section with header metadata and plugin chips.
  const PluginSection({
    super.key,
    required this.controller,
    required this.plugins,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;

    return Container(
      padding: kCardPadding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: materialTheme.cardBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          SectionHeader(
            icon: icon,
            iconBackground: accent,
            title: title,
            subtitle: subtitle,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final plugin in plugins)
                PluginCard(
                  label: plugin.label,
                  enabled: plugin.isEnabled,
                  locked: plugin.locked,
                  leadingIcon: plugin.icon,
                  accentColor: plugin.color,
                  onChanged: (value) =>
                      controller.setPluginEnabled(plugin.pluginId, value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
