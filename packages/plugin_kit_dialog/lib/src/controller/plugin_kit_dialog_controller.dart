import 'package:flutter/foundation.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'plugin_kit_dialog_draft.dart';

/// ChangeNotifier-backed controller that wraps the immutable dialog draft.
class PluginKitDialogController extends ChangeNotifier {
  /// Creates a controller bound to [runtime] and seeded with [initialSettings].
  PluginKitDialogController({
    required this.runtime,
    required RuntimeSettings initialSettings,
  }) : _draft = PluginKitDialogDraft.initial(initialSettings) {
    _pluginsById = {for (final p in runtime.plugins) p.pluginId: p};
  }

  /// Runtime being edited by this dialog controller.
  final PluginRuntime runtime;

  PluginKitDialogDraft _draft;

  /// Current immutable draft containing active and working settings.
  PluginKitDialogDraft get draft => _draft;

  /// Indexed view onto [runtime.plugins] for cheap lookups during no-op
  /// pruning. The Plugins tab still iterates `runtime.plugins` directly via
  /// [buildPluginChipsModels].
  late final Map<PluginId, Plugin> _pluginsById;

  /// Whether working settings differ from the active baseline.
  bool get isDirty => _draft.isDirty;

  bool _showAllServices = false;

  /// Whether advanced views should display all services including defaults.
  bool get showAllServices => _showAllServices;

  /// Updates [showAllServices] and notifies listeners when it changes.
  set showAllServices(bool value) {
    if (_showAllServices == value) {
      return;
    }
    _showAllServices = value;
    notifyListeners();
  }

  bool _isSaving = false;

  /// Whether a save is currently in flight. The dialog body sets this around
  /// the `onSave` await so the header can render an inline spinner, the body
  /// can dim its content, and the surrounding `showPluginKitDialog` scope can
  /// block barrier-tap and system-back dismissal.
  bool get isSaving => _isSaving;

  /// Sets [isSaving] and notifies listeners when it changes. Public so the
  /// dialog body can flip it; treat as read-only from app code.
  set isSaving(bool value) {
    if (_isSaving == value) {
      return;
    }
    _isSaving = value;
    notifyListeners();
  }

  /// Enables or disables a plugin in the working draft.
  void setPluginEnabled(PluginId pluginId, bool enabled) {
    final next = _draft.withPluginEnabled(pluginId, enabled);
    _swap(_applyPluginNoOpDeletion(next, pluginId));
  }

  /// Sets one service config value in the working draft.
  void setServiceField({
    required Pin scopedKey,
    required String fieldKey,
    required Object? value,
  }) {
    final next = _draft.withServiceField(scopedKey, fieldKey, value);
    _swap(_applyNoOpDeletion(next, scopedKey));
  }

  /// Enables or disables one service in the working draft.
  void setServiceEnabled(Pin scopedKey, bool enabled) {
    final next = _draft.withServiceEnabled(scopedKey, enabled);
    _swap(_applyNoOpDeletion(next, scopedKey));
  }

  /// Sets or clears the priority override for one service.
  void setServicePriority(Pin scopedKey, int? priority) {
    final next = _draft.withServicePriority(scopedKey, priority);
    _swap(_applyNoOpDeletion(next, scopedKey));
  }

  /// Resets one service field back to its default/absent value.
  void resetField(Pin scopedKey, String fieldKey) {
    final next = _draft.resetField(scopedKey, fieldKey);
    _swap(_applyNoOpDeletion(next, scopedKey));
  }

  /// Resets one service override to its active baseline.
  void resetService(Pin scopedKey) {
    final next = _draft.resetService(scopedKey);
    _swap(_applyNoOpDeletion(next, scopedKey));
  }

  /// Resets one plugin override to its active baseline.
  void resetPlugin(PluginId pluginId) {
    final next = _draft.resetPlugin(pluginId);
    _swap(_applyPluginNoOpDeletion(next, pluginId));
  }

  /// Resets every override back to the initial settings.
  void resetAll() {
    _swap(_draft.resetAll());
  }

  /// Replaces the working settings wholesale.
  void replaceWorking(RuntimeSettings parsed) {
    _swap(_draft.withWorking(parsed));
  }

  /// Marks the current working snapshot as the new active baseline.
  void markSaved() {
    _swap(_draft.markSaved());
  }

  void _swap(PluginKitDialogDraft next) {
    if (identical(next, _draft)) {
      return;
    }

    _draft = next;
    notifyListeners();
  }

  PluginKitDialogDraft _applyNoOpDeletion(
    PluginKitDialogDraft draft,
    Pin scopedKey,
  ) {
    return draft.applyNoOpDeletion(
      scopedKey: scopedKey,
      defaultsByFieldKey: _defaultsForScopedKey(scopedKey),
    );
  }

  PluginKitDialogDraft _applyPluginNoOpDeletion(
    PluginKitDialogDraft draft,
    PluginId pluginId,
  ) {
    final plugin = draft.working.plugins[pluginId];
    if (plugin == null) {
      return draft;
    }

    final declared = _pluginsById[pluginId];
    if (declared == null) {
      return draft;
    }
    final defaultEnabled = PluginRuntime.isPluginEnabledByDefault(declared);

    if (plugin.enabled != defaultEnabled || plugin.config.isNotEmpty) {
      return draft;
    }

    final nextPlugins = Map<PluginId, PluginConfig>.from(draft.working.plugins)
      ..remove(pluginId);
    return draft.withWorking(draft.working.copyWith(plugins: nextPlugins));
  }

  /// Returns defaults for [PluginKitDialogDraft.applyNoOpDeletion].
  ///
  /// Defaults are sourced from the target runtime's winning service
  /// registration so no-op pruning can compare against declared field defaults.
  Map<String, Object?> _defaultsForScopedKey(Pin scopedKey) {
    final ServiceRegistry registry;
    if (runtime.sessions.isNotEmpty) {
      registry = runtime.sessions.last.registry;
    } else {
      registry = runtime.globalRegistry;
    }

    final ServiceId serviceId;
    try {
      serviceId = scopedKey.serviceId;
    } on FormatException {
      return const <String, Object?>{};
    }
    final winningRegistration = registry
        .getAllResolvedRegistrations()[serviceId];
    if (winningRegistration == null) {
      return const <String, Object?>{};
    }

    final defaultsByFieldKey = <String, Object?>{};
    final configurableCapabilities = winningRegistration.capabilities
        .whereType<UiConfigurableCapability>();

    for (final capability in configurableCapabilities) {
      _collectFieldDefaults(capability.fields, defaultsByFieldKey);
    }

    return defaultsByFieldKey;
  }

  void _collectFieldDefaults(
    Iterable<ConfigField> fields,
    Map<String, Object?> output,
  ) {
    for (final field in fields) {
      if (field is GroupConfigField) {
        _collectFieldDefaults(field.children, output);
        continue;
      }
      output[field.key] = field.defaultValue;
    }
  }
}
