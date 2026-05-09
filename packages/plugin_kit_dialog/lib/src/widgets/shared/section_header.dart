import 'package:flutter/material.dart';

/// Header row with icon chip, title, and optional subtitle for sections.
class SectionHeader extends StatelessWidget {
  /// Icon shown inside the colored icon container.
  final IconData icon;

  /// Accent color used for the icon and icon container tint.
  final Color iconBackground;

  /// Primary section title text.
  final String title;

  /// Optional secondary section subtitle text.
  final String? subtitle;

  /// Optional override for the title's text style.
  final TextStyle? titleStyle;

  /// Optional override for the subtitle's text style.
  final TextStyle? subtitleStyle;

  /// Creates a section header with required icon chrome and title text.
  const SectionHeader({
    super.key,
    required this.icon,
    required this.iconBackground,
    required this.title,
    this.subtitle,
    this.titleStyle,
    this.subtitleStyle,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconBackground.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: iconBackground),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle ?? textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style:
                      subtitleStyle ??
                      textTheme.bodyMedium?.copyWith(height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
