import 'package:flutter/material.dart';

import '../../theme/plugin_kit_dialog_theme.dart';
import '../../theme/plugin_kit_dialog_tokens.dart';

/// Compact KPI card used by the Plugins tab stat row (Spec §9.8).
class PluginStatCard extends StatelessWidget {
  /// Icon rendered inside the leading icon box.
  final IconData icon;

  /// Accent tint used for the icon box background and icon color.
  final Color iconBackground;

  /// Enabled/active count shown as the numerator.
  final int numerator;

  /// Total count shown as the denominator.
  final int denominator;

  /// Secondary label shown under the count.
  final String label;

  /// Creates a stat card with icon, ratio text, and label.
  const PluginStatCard({
    super.key,
    required this.icon,
    required this.iconBackground,
    required this.numerator,
    required this.denominator,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;
    final textTheme = materialTheme.textTheme;
    final countStyle = textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final iconColor =
        ThemeData.estimateBrightnessForColor(iconBackground) == Brightness.dark
        ? colorScheme.onPrimary
        : colorScheme.onSurface;

    return Container(
      padding: kCardPadding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: materialTheme.cardBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$numerator / $denominator', style: countStyle),
                Text(label, style: textTheme.bodyMedium?.copyWith(height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
