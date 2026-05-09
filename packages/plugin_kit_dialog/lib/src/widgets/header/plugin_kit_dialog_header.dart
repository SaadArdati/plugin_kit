import 'dart:async';

import 'package:flutter/material.dart';

import '../../controller/plugin_kit_dialog_controller.dart';
import '../../runtime/events.dart';
import 'unsaved_badge.dart';

/// Single-row dialog header: tabs + unsaved badge on the left, reset + cancel
/// + save actions on the right. The macOS-style chrome from earlier drafts is
/// intentionally dropped: this is a widget embedded in a Material Dialog,
/// not a bespoke window frame.
class PluginKitDialogHeader extends StatelessWidget {
  /// Controller used for dirty state, reset actions, and save-button enablement.
  final PluginKitDialogController controller;

  /// Available tabs contributed by runtime plugins.
  final List<TabDescriptor> tabs;

  /// Id of the currently active tab.
  final String? activeTabId;

  /// Callback fired when a tab pill is selected.
  final ValueChanged<String> onTabSelected;

  /// Callback fired when the user presses Cancel.
  final VoidCallback onCancel;

  /// Callback fired when the user presses Save.
  final FutureOr<void> Function() onSave;

  /// Whether a save is currently in flight. When true, all header buttons are
  /// disabled and the Save button shows an inline spinner.
  final bool isSaving;

  /// Creates the dialog header.
  const PluginKitDialogHeader({
    required this.controller,
    required this.tabs,
    required this.activeTabId,
    required this.onTabSelected,
    required this.onCancel,
    required this.onSave,
    this.isSaving = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final orderedTabs = tabs.toList(growable: false)
      ..sort((a, b) => a.order.compareTo(b.order));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < orderedTabs.length; index++) ...[
                    _TabPill(
                      tab: orderedTabs[index],
                      active: orderedTabs[index].id == activeTabId,
                      onPressed: () => onTabSelected(orderedTabs[index].id),
                    ),
                    if (index < orderedTabs.length - 1)
                      const SizedBox(width: 6),
                  ],
                  if (orderedTabs.isNotEmpty) const SizedBox(width: 12),
                  ListenableBuilder(
                    listenable: controller,
                    builder: (_, _) =>
                        UnsavedBadge(visible: controller.isDirty),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) => IconButton(
              tooltip: 'Reset all',
              onPressed: !isSaving && controller.isDirty
                  ? controller.resetAll
                  : null,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: isSaving ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onSurface.withValues(alpha: 0.72),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (_, _) {
              final canSave = controller.isDirty && !isSaving;
              return FilledButton.icon(
                onPressed: canSave ? () => onSave() : null,
                icon: isSaving
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : const Icon(Icons.check, size: 18),
                label: Text(isSaving ? 'Saving…' : 'Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  disabledBackgroundColor: isSaving
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                  disabledForegroundColor: isSaving
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.tab,
    required this.active,
    required this.onPressed,
  });

  final TabDescriptor tab;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final borderRadius = const BorderRadius.all(Radius.circular(8));

    final backgroundColor = active ? colorScheme.primary : Colors.transparent;
    final foregroundColor = active
        ? colorScheme.onPrimary
        : colorScheme.onSurface.withValues(alpha: 0.72);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: borderRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme.merge(
                data: IconThemeData(size: 16, color: foregroundColor),
                child: tab.icon,
              ),
              const SizedBox(width: 6),
              Text(
                tab.label,
                style: textTheme.labelSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
