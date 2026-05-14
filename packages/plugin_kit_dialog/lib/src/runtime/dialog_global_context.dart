import 'package:flutter/foundation.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../controller/plugin_kit_dialog_controller.dart';
import '../utils.dart';

/// Custom [GlobalPluginContext] consumed by the dialog's internal runtime
/// plugins.
///
/// The dialog runtime is built per-invocation and lives for one open-close
/// cycle, so the runtime itself is the dialog's scope; there's no nested
/// session. All dialog plugins are `GlobalPlugin<DialogGlobalContext>` and
/// receive this context typed directly in `attach`, with no
/// `sessions.last.context` cast.
class DialogGlobalContext extends GlobalPluginContext {
  /// Runtime being edited by the dialog (the host app's runtime).
  final PluginRuntime runtime;

  /// Controller that stores and mutates dialog draft state.
  final PluginKitDialogController controller;

  /// Save callback invoked with working settings.
  final SaveCallback onSave;

  /// Cancel callback invoked when the dialog is dismissed without saving.
  final VoidCallback onCancel;

  /// Creates a dialog global context with runtime, controller, theme, and
  /// callbacks.
  DialogGlobalContext({
    required super.registry,
    required super.bus,
    super.sessions,
    super.extras,
    required this.runtime,
    required this.controller,
    required this.onSave,
    required this.onCancel,
  });

  @override
  DialogGlobalContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
    List<PluginSession<SessionPluginContext>>? sessions,
  }) {
    return DialogGlobalContext(
      registry: registry ?? this.registry.copy(),
      bus: bus ?? this.bus,
      sessions: sessions ?? this.sessions,
      extras: extras ?? this.extras,
      runtime: runtime,
      controller: controller,
      onSave: onSave,
      onCancel: onCancel,
    );
  }
}
