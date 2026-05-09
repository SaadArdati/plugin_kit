import 'package:flutter/material.dart';

import '../../theme/plugin_kit_dialog_theme.dart';
import '../../theme/plugin_kit_dialog_tokens.dart';

/// Reusable rounded panel chrome for dialog cards.
class PluginKitDialogCard extends StatelessWidget {
  /// Optional header widget shown above [child].
  final Widget? header;

  /// Optional body content rendered inside the card.
  final Widget? child;

  /// Optional card padding override. Defaults to [kCardPadding].
  final EdgeInsetsGeometry? padding;

  /// Clip behavior used for ink effects and descendants.
  final Clip clipBehavior;

  /// Creates a themed card shell with optional [header] and [child] slots.
  const PluginKitDialogCard({
    super.key,
    this.header,
    this.child,
    this.padding,
    this.clipBehavior = Clip.none,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;

    return Container(
      padding: padding ?? kCardPadding,
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: materialTheme.cardBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: _CardContent(header: header, child: child),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({required this.header, required this.child});

  final Widget? header;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (header == null && child == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        if (header != null && child != null) const SizedBox(height: 8),
        ?child,
      ],
    );
  }
}
