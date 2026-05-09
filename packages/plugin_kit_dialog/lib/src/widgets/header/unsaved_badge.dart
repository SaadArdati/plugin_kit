import 'package:flutter/material.dart';

import '../../theme/plugin_kit_dialog_theme.dart';

/// Compact pill badge that signals unsaved dialog changes (Spec §9.4).
class UnsavedBadge extends StatelessWidget {
  /// Whether the badge is visible.
  final bool visible;

  /// Creates an unsaved badge that collapses when [visible] is false.
  const UnsavedBadge({required this.visible, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = PluginKitDialogTheme.of(context);

    return Visibility(
      visible: visible,
      replacement: const SizedBox.shrink(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: theme.experimentalAccent.withValues(alpha: 0.12),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          border: Border.all(
            color: theme.experimentalAccent.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.experimentalAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Unsaved',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: theme.experimentalAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
