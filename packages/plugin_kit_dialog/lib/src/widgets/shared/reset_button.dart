import 'package:flutter/material.dart';

/// Refresh-action button used to reset a value to its default.
class ResetButton extends StatelessWidget {
  /// Whether the current value differs from the default.
  final bool isOverridden;

  /// Callback fired when the user requests a reset.
  final VoidCallback onReset;

  /// Creates a reset icon button with muted, inert state when not overridden.
  const ResetButton({
    super.key,
    required this.isOverridden,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: onReset,
      icon: const Icon(Icons.refresh),
      iconSize: 14,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 22, height: 22),
      visualDensity: VisualDensity.compact,
      splashRadius: 14,
      tooltip: 'Reset to default',
    );

    if (isOverridden) {
      return button;
    }

    return IgnorePointer(child: Opacity(opacity: 0.4, child: button));
  }
}
