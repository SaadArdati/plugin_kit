import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

import '../../theme/plugin_kit_dialog_theme.dart';

/// Section header card that groups all service cards belonging to the same
/// [namespace] under a single collapsible block on the Services tab.
///
/// The header shows the namespace's [PluginKitVisual] (icon, label, optional
/// description). Tapping the header toggles expansion. When [expanded] is
/// false, [children] are not painted.
class NamespaceSectionCard extends StatelessWidget {
  /// Namespace for the section header. Its [Namespace.value] is used as the
  /// fallback label if [visual] is null or omits a label.
  final Namespace namespace;

  /// Optional visual override for the namespace (label, description, icon,
  /// color). Falls back to [namespace] string and theme defaults when null.
  final PluginKitVisual? visual;

  /// Whether the section is expanded. When false, [children] are hidden.
  final bool expanded;

  /// Invoked when the user taps the header to toggle [expanded].
  final VoidCallback onToggleExpanded;

  /// Service cards to render inside the section when expanded.
  final List<Widget> children;

  /// Creates a namespace section card.
  const NamespaceSectionCard({
    super.key,
    required this.namespace,
    required this.visual,
    required this.expanded,
    required this.onToggleExpanded,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = visual?.color ?? colorScheme.primary;
    final label = visual?.label ?? namespace.value;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: theme.cardBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: IconTheme.merge(
                        data: IconThemeData(size: 16, color: accent),
                        child:
                            visual?.icon ?? const Icon(Icons.folder_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                              height: 1.15,
                            ),
                          ),
                          if (visual?.description != null &&
                              visual!.description!.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              visual!.description!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i != children.length - 1) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
