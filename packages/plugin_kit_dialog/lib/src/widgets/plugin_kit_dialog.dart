import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../controller/plugin_kit_dialog_controller.dart';
import '../theme/plugin_kit_dialog_theme.dart';
import '../utils.dart';
import 'plugin_kit_dialog_body.dart';

/// Material dialog shell that hosts [PluginKitDialogBody].
// #docregion plugin-kit-dialog-plugin-kit-dialog
class PluginKitDialog extends StatelessWidget {
  /// Controller backing draft edits, dirty state, and save/reset behavior.
  /// The runtime being edited is read from `controller.runtime`.
  final PluginKitDialogController controller;

  /// Save callback invoked with the draft settings.
  final SaveCallback onSave;

  /// Cancel callback invoked when dialog dismissal is requested.
  final VoidCallback onCancel;

  /// Creates a constrained material dialog around [PluginKitDialogBody].
  const PluginKitDialog({
    required this.controller,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const borderRadius = BorderRadius.all(Radius.circular(20));
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: colorScheme.surface,
      elevation: 24,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: PluginKitDialogBody(
          controller: controller,
          runtime: controller.runtime,
          onSave: onSave,
          onCancel: onCancel,
        ),
      ),
    );
  }
}
// #enddocregion plugin-kit-dialog-plugin-kit-dialog

/// Opens [PluginKitDialog] and resolves with saved settings or `null` on cancel.
// #docregion plugin-kit-dialog-show-plugin-kit-dialog
Future<RuntimeSettings?> showPluginKitDialog({
  required BuildContext context,
  required PluginRuntime runtime,
  required RuntimeSettings initialSettings,
  required SaveCallback onSave,
  String title = 'Plugin Kit',
  PluginKitDialogTheme? theme,
  bool barrierDismissible = true,
}) async {
  // #enddocregion plugin-kit-dialog-show-plugin-kit-dialog
  final controller = PluginKitDialogController(
    runtime: runtime,
    initialSettings: initialSettings,
  );

  Future<void> handleCancel(BuildContext dialogContext) async {
    // Don't let cancel run while a save is mid-flight: the user just clicked
    // through the spinner and there's nothing meaningful to cancel.
    if (controller.isSaving) {
      return;
    }
    final shouldDiscard = await _shouldDiscardUnsavedChanges(
      context: dialogContext,
      controller: controller,
    );
    if (!dialogContext.mounted || !shouldDiscard) {
      return;
    }
    Navigator.of(dialogContext).pop(null);
  }

  Future<void> handleSave(
    BuildContext dialogContext,
    RuntimeSettings settings,
  ) async {
    await onSave(settings);
    if (!dialogContext.mounted) {
      return;
    }
    Navigator.of(dialogContext).pop(settings);
  }

  return showDialog<RuntimeSettings?>(
    context: context,
    // Defeat tap-outside dismissal whenever a save is in flight; the inner
    // _SavingOverlay already blocks pointer events inside the dialog.
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final dialog = ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return PopScope<RuntimeSettings?>(
            // While saving, swallow back-button presses entirely. Otherwise
            // route through the cancel/discard flow.
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || controller.isSaving) {
                return;
              }
              unawaited(handleCancel(dialogContext));
            },
            child: PluginKitDialog(
              controller: controller,
              onSave: (settings) => handleSave(dialogContext, settings),
              onCancel: () => handleCancel(dialogContext),
            ),
          );
        },
      );

      if (theme == null) {
        return dialog;
      }

      // Wrap inside the showDialog builder, not at the call site: the dialog
      // route lives under the root navigator, so any Theme above
      // showPluginKitDialog wouldn't propagate down here. Preserve the host's
      // other ThemeExtensions so we don't silently nuke them: copy the
      // existing map (keyed by Type) and override our slot.
      final base = Theme.of(dialogContext);
      final mergedExtensions = Map.of(base.extensions)
        ..[PluginKitDialogTheme] = theme;
      return Theme(
        data: base.copyWith(extensions: mergedExtensions.values),
        child: dialog,
      );
    },
  );
}

Future<bool> _shouldDiscardUnsavedChanges({
  required BuildContext context,
  required PluginKitDialogController controller,
}) async {
  if (!controller.isDirty) {
    return true;
  }

  final shouldDiscard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Discard unsaved changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      );
    },
  );

  return shouldDiscard ?? false;
}
