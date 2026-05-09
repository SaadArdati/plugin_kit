import 'package:plugin_kit/plugin_kit.dart';

/// Immutable pair of active and working settings used for dialog edits (Spec §6.2).
class PluginKitDialogDraft {
  /// The settings in effect when the dialog opened (or after the last
  /// successful save). Used as the dirty-check baseline.
  final RuntimeSettings active;

  /// The settings the user is currently editing.
  final RuntimeSettings working;

  const PluginKitDialogDraft._(this.active, this.working);

  /// Creates a draft whose active and working snapshots both match [settings].
  factory PluginKitDialogDraft.initial(RuntimeSettings settings) =>
      PluginKitDialogDraft._(settings, settings);

  /// Whether [working] differs from [active].
  bool get isDirty => active != working;

  /// Plugin IDs whose enabled/config differ between [active] and [working].
  Set<PluginId> get dirtyPluginIds => {
    for (final pluginId in {...active.plugins.keys, ...working.plugins.keys})
      if (active.plugins[pluginId] != working.plugins[pluginId]) pluginId,
  };

  /// Service scoped-keys (`plugin:service`) whose config/priority differ
  /// between [active] and [working].
  Set<Pin> get dirtyServiceKeys => {
    for (final scopedKey in {...active.services.keys, ...working.services.keys})
      if (active.services[scopedKey] != working.services[scopedKey]) scopedKey,
  };

  /// Returns a new draft with [pluginId] enabled/disabled in [working].
  PluginKitDialogDraft withPluginEnabled(PluginId pluginId, bool enabled) {
    final existingConfig = working.plugins[pluginId]?.config ?? const {};
    final nextPlugins = {...working.plugins}
      ..[pluginId] = PluginConfig(enabled: enabled, config: existingConfig);
    return withWorking(working.copyWith(plugins: nextPlugins));
  }

  /// Returns a new draft with one service field updated in [working].
  PluginKitDialogDraft withServiceField(
    Pin scopedKey,
    String fieldKey,
    Object? value,
  ) {
    final existing = working.services[scopedKey] ?? const ServiceSettings();
    final nextConfig = _setDottedValue(existing.config, fieldKey, value);
    final nextServices = {...working.services}
      ..[scopedKey] = existing.copyWith(config: nextConfig);
    return withWorking(working.copyWith(services: nextServices));
  }

  /// Returns a new draft with one service enablement updated in [working].
  PluginKitDialogDraft withServiceEnabled(Pin scopedKey, bool enabled) {
    final existing = working.services[scopedKey] ?? const ServiceSettings();
    final nextServices = {...working.services}
      ..[scopedKey] = ServiceSettings(
        enabled: enabled,
        config: existing.config,
        priority: existing.priority,
      );
    return withWorking(working.copyWith(services: nextServices));
  }

  /// Returns a new draft with one service priority updated in [working].
  PluginKitDialogDraft withServicePriority(Pin scopedKey, int? priority) {
    final existing = working.services[scopedKey] ?? const ServiceSettings();
    final nextServices = {...working.services}
      ..[scopedKey] = ServiceSettings(
        enabled: existing.enabled,
        config: existing.config,
        priority: priority,
      );
    return withWorking(working.copyWith(services: nextServices));
  }

  /// Returns a new draft that keeps [active] and replaces [working] with [next].
  PluginKitDialogDraft withWorking(RuntimeSettings next) =>
      PluginKitDialogDraft._(active, next);

  /// Returns a new draft with one service field cleared in [working].
  PluginKitDialogDraft resetField(Pin scopedKey, String fieldKey) {
    final existing = working.services[scopedKey] ?? const ServiceSettings();
    final nextConfig = _setDottedValue(existing.config, fieldKey, null);
    final nextServices = {...working.services}
      ..[scopedKey] = existing.copyWith(config: nextConfig);
    return withWorking(working.copyWith(services: nextServices));
  }

  /// Returns a new draft with one service restored from [active].
  PluginKitDialogDraft resetService(Pin scopedKey) {
    final nextServices = {...working.services};
    final activeEntry = active.services[scopedKey];
    if (activeEntry == null) {
      nextServices.remove(scopedKey);
    } else {
      nextServices[scopedKey] = activeEntry;
    }
    return withWorking(working.copyWith(services: nextServices));
  }

  /// Returns a new draft with one plugin restored from [active].
  PluginKitDialogDraft resetPlugin(PluginId pluginId) {
    final nextPlugins = {...working.plugins};
    final activeEntry = active.plugins[pluginId];
    if (activeEntry == null) {
      nextPlugins.remove(pluginId);
    } else {
      nextPlugins[pluginId] = activeEntry;
    }
    return withWorking(working.copyWith(plugins: nextPlugins));
  }

  /// Returns a new draft with all overrides reset to [active].
  PluginKitDialogDraft resetAll() => PluginKitDialogDraft._(active, active);

  /// Returns a new draft that promotes [working] to the new active baseline.
  PluginKitDialogDraft markSaved() => PluginKitDialogDraft._(working, working);

  /// Deletes `working.services[scopedKey]` when it is a no-op override.
  ///
  /// [defaultsByFieldKey] must map each declared `ConfigField.key` (dotted
  /// path such as `model.provider`) to that field's default value for the
  /// target service. The controller precomputes this map from
  /// `UiConfigurableCapability` schemas and calls this method after each
  /// `withServiceField` / `resetField` mutation.
  PluginKitDialogDraft applyNoOpDeletion({
    required Pin scopedKey,
    required Map<String, Object?> defaultsByFieldKey,
  }) {
    final service = working.services[scopedKey];
    if (service == null) {
      return this;
    }

    if (!_isNoOpOverride(service, defaultsByFieldKey)) {
      return this;
    }

    final nextServices = {...working.services}..remove(scopedKey);
    return withWorking(working.copyWith(services: nextServices));
  }

  bool _isNoOpOverride(
    ServiceSettings service,
    Map<String, Object?> defaultsByFieldKey,
  ) {
    if (!service.enabled || service.priority != null) {
      return false;
    }

    // Every path actually present in config must (a) correspond to a declared
    // field AND (b) equal that field's default. Paths declared by the schema
    // but ABSENT from config are implicitly "using default" and don't prevent
    // no-op detection: that's the whole point of resetField().
    final declaredPaths = defaultsByFieldKey.keys.toSet();
    final actualPaths = <String>{};
    _collectLeafPaths(service.config, actualPaths);

    for (final path in actualPaths) {
      if (!declaredPaths.contains(path)) {
        return false;
      }
      final current = _readDottedValue(service.config, path);
      if (!_deepEquals(current, defaultsByFieldKey[path])) {
        return false;
      }
    }

    return true;
  }

  static Map<String, dynamic> _setDottedValue(
    Map<String, dynamic> source,
    String dottedKey,
    Object? value,
  ) {
    final segments = dottedKey
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return {...source};
    }

    final root = {...source};
    _setRecursive(root, segments, value);
    return root;
  }

  static void _setRecursive(
    Map<String, dynamic> node,
    List<String> segments,
    Object? value,
  ) {
    final key = segments.first;
    if (segments.length == 1) {
      if (value == null) {
        node.remove(key);
      } else {
        node[key] = value;
      }
      return;
    }

    final existingChild = node[key];
    final child = existingChild is Map<String, dynamic>
        ? {...existingChild}
        : <String, dynamic>{};

    _setRecursive(child, segments.sublist(1), value);

    if (child.isEmpty) {
      node.remove(key);
    } else {
      node[key] = child;
    }
  }

  static Object? _readDottedValue(
    Map<String, dynamic> source,
    String dottedKey,
  ) {
    final segments = dottedKey
        .split('.')
        .where((segment) => segment.isNotEmpty);
    Object? current = source;

    for (final segment in segments) {
      if (current is! Map<String, dynamic>) {
        return null;
      }
      current = current[segment];
    }

    return current;
  }

  static void _collectLeafPaths(
    Map<String, dynamic> source,
    Set<String> output, [
    String prefix = '',
  ]) {
    source.forEach((key, value) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      if (value is Map<String, dynamic>) {
        _collectLeafPaths(value, output, path);
      } else {
        output.add(path);
      }
    });
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) {
      return true;
    }

    // Number-aware equality: slider widgets always write `double` even when
    // the plugin author's `defaultValue` is an `int`. Treat 3 and 3.0 as the
    // same value so moving a slider back to its integer default correctly
    // collapses the override.
    if (a is num && b is num) {
      return a.toDouble() == b.toDouble();
    }

    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }

    if (a is Set && b is Set) {
      if (a.length != b.length) {
        return false;
      }
      for (final value in a) {
        if (!b.contains(value)) {
          return false;
        }
      }
      return true;
    }

    return a == b;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PluginKitDialogDraft &&
        active == other.active &&
        working == other.working;
  }

  @override
  int get hashCode => Object.hash(active, working);
}
