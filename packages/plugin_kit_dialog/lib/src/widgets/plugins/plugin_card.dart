import 'package:flutter/material.dart';

import '../../theme/plugin_kit_dialog_theme.dart';

/// Toggleable plugin card with a soft accent gradient background and a faded
/// background icon (Spec §9.9). Renders checked, unchecked, and locked
/// variants. Locked plugins show a padlock in place of the checkbox; enabled
/// plugins surface a stronger accent than unselected ones so the "on" state
/// reads at a glance.
class PluginCard extends StatelessWidget {
  /// Card label, typically a plugin id.
  final String label;

  /// Whether the plugin is enabled in the current draft.
  final bool enabled;

  /// Whether the plugin is locked and cannot be toggled. Locked plugins are
  /// always on; the lock glyph replaces the checkbox.
  final bool locked;

  /// Optional widget rendered large and faded behind the foreground content,
  /// pinned to the top-right corner. Sourced from `PluginKitVisual.icon` when
  /// an override is registered. Wrapped in an [IconTheme] seeded with a
  /// dimmed accent and a 92-px size.
  final Widget? leadingIcon;

  /// Optional accent color override sourced from `PluginKitVisual.color`.
  /// When null, falls back to the theme's primary color.
  final Color? accentColor;

  /// Callback invoked with the next enabled state when tapped.
  final ValueChanged<bool> onChanged;

  /// Creates a plugin toggle card.
  const PluginCard({
    super.key,
    required this.label,
    required this.enabled,
    required this.locked,
    required this.onChanged,
    this.leadingIcon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;
    final radius = materialTheme.cardBorderRadius;

    final accent = accentColor ?? colorScheme.primary;
    // Locked plugins are conceptually "on": they share the active accent
    // treatment so they don't read as disabled or broken.
    final active = enabled || locked;

    final IconData stateIcon;
    final Color stateIconColor;
    if (locked) {
      stateIcon = Icons.lock_rounded;
      stateIconColor = accent;
    } else if (enabled) {
      stateIcon = Icons.check_box_rounded;
      stateIconColor = accent;
    } else {
      stateIcon = Icons.check_box_outline_blank_rounded;
      stateIconColor = colorScheme.onSurface.withValues(alpha: 0.45);
    }

    // Locked cards intentionally drop the border so they read as embedded
    // system surfaces, not toggleable controls.
    final Color? borderColor;
    if (locked) {
      borderColor = null;
    } else if (active) {
      borderColor = accent.withValues(alpha: 0.55);
    } else {
      borderColor = colorScheme.outlineVariant;
    }
    final gradientStart = accent.withValues(alpha: active ? 0.20 : 0.07);
    final gradientEnd = accent.withValues(alpha: active ? 0.03 : 0.0);
    final backgroundIconColor = accent.withValues(alpha: active ? 0.32 : 0.14);

    return IgnorePointer(
      ignoring: locked,
      child: SizedBox(
        width: 140,
        height: 140,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: borderColor == null
                  ? null
                  : Border.all(color: borderColor),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [gradientStart, gradientEnd],
              ),
            ),
            child: InkWell(
              onTap: () => onChanged(!enabled),
              child: Stack(
                children: [
                  if (leadingIcon != null)
                    Positioned(
                      right: -14,
                      top: -16,
                      child: IconTheme.merge(
                        data: IconThemeData(
                          size: 92,
                          color: backgroundIconColor,
                        ),
                        child: leadingIcon!,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(stateIcon, size: 24, color: stateIconColor),
                        const Spacer(),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.92,
                                ),
                                fontWeight: FontWeight.w500,
                                height: 1.25,
                                letterSpacing: 0.1,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
