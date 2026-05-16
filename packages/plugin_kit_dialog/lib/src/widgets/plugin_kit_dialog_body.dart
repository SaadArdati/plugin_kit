import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/plugins_tab_plugin.dart';

import '../controller/plugin_kit_dialog_controller.dart';
import '../runtime/dialog_global_context.dart';
import '../runtime/events.dart';
import '../runtime/plugins/advanced_tab_plugin.dart';
import '../runtime/plugins/default_field_renderers_plugin.dart';
import '../runtime/plugins/services_tab_plugin.dart';
import '../utils.dart';
import 'header/plugin_kit_dialog_header.dart';

/// Bare dialog body that wires header chrome and active-tab content (Spec §9.2).
// #docregion plugin-kit-dialog-body-plugin-kit-dialog-body
class PluginKitDialogBody extends StatefulWidget {
  /// Controller backing the editable draft state and dirty tracking.
  final PluginKitDialogController controller;

  /// Runtime being edited by this dialog.
  final PluginRuntime runtime;

  /// Save callback invoked with current working settings.
  final SaveCallback onSave;

  /// Cancel callback invoked when the user cancels out of the dialog.
  final VoidCallback onCancel;

  /// Creates a dialog body bound to [controller] and [runtime].
  const PluginKitDialogBody({
    required this.controller,
    required this.runtime,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  @override
  State<PluginKitDialogBody> createState() => _PluginKitDialogBodyState();
}
// #enddocregion plugin-kit-dialog-body-plugin-kit-dialog-body

class _PluginKitDialogBodyState extends State<PluginKitDialogBody> {
  late final PluginRuntime<DialogGlobalContext, SessionPluginContext> _runtime;

  EventBus get _bus => _runtime.globalBus;

  late final List<TabDescriptor> _tabs;

  String? _activeTabId;

  TabDescriptor get _activeTab {
    return _tabs.firstWhere(
      (tab) => tab.id == _activeTabId,
      orElse: () => _tabs.first,
    );
  }

  bool get _isSaving => widget.controller.isSaving;

  @override
  void initState() {
    super.initState();

    _runtime = PluginRuntime<DialogGlobalContext, SessionPluginContext>(
      plugins: [
        PluginsTabPlugin(),
        FieldRenderersPlugin(),
        ServicesTabPlugin(),
        AdvancedTabPlugin(),
      ],
    );

    _runtime.init(
      globalContextFactory: (registry, bus, sessions) => DialogGlobalContext(
        registry: registry,
        bus: bus,
        sessions: sessions,
        runtime: widget.runtime,
        controller: widget.controller,
        onSave: widget.onSave,
        onCancel: widget.onCancel,
      ),
    );

    final collectTabs = _bus
        .emitSync<CollectTabsEvent>(event: CollectTabsEvent())
        .event
        .tabs;

    _tabs = [...collectTabs]..sort((a, b) => a.order.compareTo(b.order));

    _activeTabId = _tabs.isEmpty ? 'plugins' : _tabs.first.id;
  }

  @override
  void dispose() {
    // Flutter's State.dispose is sync; the runtime's dispose is async.
    // Route any error -- sync OR async -- through FlutterError.reportError
    // via the package-local helper so a plugin throwing during detach
    // surfaces in tester.takeException() and in production logs, instead
    // of escaping as an uncaught zone error.
    disposeAndReport(
      _runtime.dispose,
      contextDescription:
          'disposing PluginRuntime on PluginKitDialogBody unmount',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final isSaving = _isSaving;
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PluginKitDialogHeader(
                  controller: widget.controller,
                  tabs: _tabs,
                  activeTabId: _activeTabId,
                  onTabSelected: (tabId) {
                    if (isSaving || tabId == _activeTabId) {
                      return;
                    }
                    setState(() => _activeTabId = tabId);
                  },
                  onCancel: widget.onCancel,
                  onSave: _handleSave,
                  isSaving: isSaving,
                ),
                Expanded(child: _activeTab.builder(context)),
              ],
            ),
            if (isSaving)
              Positioned.fill(
                child: _SavingOverlay(
                  barrierColor: colorScheme.surface.withValues(alpha: 0.55),
                  spinnerColor: colorScheme.primary,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) {
      return;
    }
    widget.controller.isSaving = true;
    try {
      await widget.onSave(widget.controller.draft.working);
      // The default outer `handleSave` in showPluginKitDialog pops the
      // route between the await and the mounted check, so a `!mounted`
      // short-circuit would skip markSaved() entirely and leave isDirty
      // true after a successful save. markSaved() mutates only the
      // controller (which outlives the dialog widget), so it is safe to
      // call before checking `mounted`; nothing past this line touches
      // widget state. Mirrors the `finally` block that clears isSaving
      // regardless of mounted.
      widget.controller.markSaved();
      if (!mounted) {
        return;
      }
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      debugPrintStack(
        label: 'PluginKitDialog save failed: $error',
        stackTrace: stackTrace,
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $error')));
    } finally {
      // Always clear the flag, even when the dialog has unmounted, so a
      // controller reused outside the dialog doesn't stay stuck "saving".
      widget.controller.isSaving = false;
    }
  }
}

/// Full-bleed modal barrier + centered spinner shown while [onSave] is in
/// flight. Absorbs all pointer events so the user can't keep editing or
/// double-trigger Save.
class _SavingOverlay extends StatelessWidget {
  const _SavingOverlay({
    required this.barrierColor,
    required this.spinnerColor,
  });

  final Color barrierColor;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Absorb taps + dim everything below.
        ModalBarrier(color: barrierColor, dismissible: false),
        Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
            ),
          ),
        ),
      ],
    );
  }
}
