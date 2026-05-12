import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../../plugin_kit_dialog.dart';
import '../../theme/plugin_kit_dialog_theme.dart';
import '../shared/compact_switch.dart';
import '../shared/reset_button.dart';
import 'priority_badge.dart';
import 'service_field_section.dart';

/// Expandable outer card for one target runtime service (Spec §9.12).
///
/// Owns the service-level controls (priority override, reset, enable) because
/// those apply to the whole registration, not per-capability. When the
/// service has a single capability, the card title is that capability's
/// label and the inner section header is suppressed; multi-capability cards
/// keep a per-capability subheader inside the body.
///
/// Expansion is controlled via [expanded] + [onToggleExpanded] so the
/// enclosing tab can retain state across `ListView` recycling.
class ServiceCard extends StatelessWidget {
  /// Plugin id that owns the service registration.
  final PluginId pluginId;

  /// Service id from the target runtime registry.
  final ServiceId serviceId;

  /// Winning registration priority displayed in the header badge.
  final int priority;

  /// One or more configurable capabilities attached to this service.
  final List<UiConfigurableCapability> capabilities;

  /// Service-axis visual override.
  final PluginKitVisual? serviceVisual;

  /// Namespace-axis visual for the service's namespace. Used as the second
  /// fallback for the color cascade when [serviceVisual] omits a color.
  final PluginKitVisual? namespaceVisual;

  /// Plugin-axis visual for [pluginId]. Used as the third fallback in the
  /// color cascade.
  final PluginKitVisual? pluginVisual;

  /// Dialog controller that stores and updates draft settings.
  final PluginKitDialogController controller;

  /// Resolves a renderer for each [ConfigField] in [capabilities].
  final FieldRenderResolver resolveRenderer;

  /// Whether this card is currently expanded.
  final bool expanded;

  /// Invoked when the user taps the header to toggle expansion.
  final VoidCallback? onToggleExpanded;

  /// Creates an expandable service card.
  const ServiceCard({
    super.key,
    required this.pluginId,
    required this.serviceId,
    required this.priority,
    required this.capabilities,
    required this.controller,
    required this.resolveRenderer,
    this.serviceVisual,
    this.namespaceVisual,
    this.pluginVisual,
    this.expanded = false,
    this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final scopedKey = pluginId.service(serviceId);
    final singleCap = capabilities.length == 1;
    final firstCap = capabilities.first;

    final title = singleCap ? firstCap.label : pluginId;
    final subtitle = singleCap
        ? firstCap.description
        : '${capabilities.length} configurable services';

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final materialTheme = Theme.of(context);
        final colorScheme = materialTheme.colorScheme;
        final serviceEnabled =
            controller.draft.working.services[scopedKey]?.enabled ?? true;
        final overriddenPriority =
            controller.draft.working.services[scopedKey]?.priority;
        final resolvedPriority = overriddenPriority ?? priority;
        final isDirty = controller.draft.dirtyServiceKeys.contains(scopedKey);

        final accentColor =
            serviceVisual?.color ??
            namespaceVisual?.color ??
            pluginVisual?.color ??
            colorScheme.primary;
        // Default to a generic gear when the service visual omits an icon.
        // Namespace icon falls through; plugin icon does not bleed into
        // service cards (plugin badge surface is separate).
        final leadingIcon =
            serviceVisual?.icon ??
            namespaceVisual?.icon ??
            const Icon(Icons.settings_outlined);
        final headerIconBackground = serviceEnabled
            ? accentColor.withValues(alpha: 0.16)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.68);
        final headerIconColor = serviceEnabled
            ? accentColor
            : colorScheme.onSurfaceVariant;
        final titleColor = serviceEnabled
            ? colorScheme.onSurface
            : colorScheme.onSurface.withValues(alpha: 0.68);
        final subtitleColor = serviceEnabled
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.72);

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: materialTheme.cardBorderRadius,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onToggleExpanded,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: headerIconBackground,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: IconTheme.merge(
                            data: IconThemeData(
                              size: 15,
                              color: headerIconColor,
                            ),
                            child: leadingIcon,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: materialTheme.textTheme.titleSmall
                                    ?.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: titleColor,
                                      height: 1.15,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (subtitle != null && subtitle.isNotEmpty) ...[
                                const SizedBox(height: 1),
                                Text(
                                  subtitle,
                                  style: materialTheme.textTheme.labelSmall
                                      ?.copyWith(
                                        fontSize: 11,
                                        color: subtitleColor,
                                        height: 1.2,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (expanded) ...[
                          PriorityBadge(
                            pluginId: pluginId,
                            priority: resolvedPriority,
                            overridePriority: overriddenPriority,
                            onPriorityChanged: (next) =>
                                controller.setServicePriority(scopedKey, next),
                          ),
                          const SizedBox(width: 4),
                          ResetButton(
                            isOverridden: isDirty,
                            onReset: () => controller.resetService(scopedKey),
                          ),
                          const SizedBox(width: 4),
                        ],
                        CompactSwitch(
                          value: serviceEnabled,
                          onChanged: (value) =>
                              controller.setServiceEnabled(scopedKey, value),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: serviceEnabled
                              ? colorScheme.onSurface
                              : colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var index = 0;
                        index < capabilities.length;
                        index++
                      ) ...[
                        ServiceFieldSection(
                          capability: capabilities[index],
                          pluginId: pluginId,
                          controller: controller,
                          scopedKey: scopedKey,
                          fieldsEnabled: serviceEnabled,
                          showHeader: !singleCap,
                          resolveRenderer: resolveRenderer,
                        ),
                        if (index != capabilities.length - 1)
                          const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
