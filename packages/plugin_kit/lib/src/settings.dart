import 'package:collection/collection.dart';
import 'package:plugin_kit/src/typed_handles.dart';

/// Deep-copy a JSON-shaped Map so the result shares no mutable state with
/// the source. Used at every boundary that hands out or accepts a `config`
/// map so caller-owned references cannot mutate runtime-held settings (and
/// vice versa). Nested Maps and Lists are recursively copied; primitives
/// (and `null`) are returned as-is.
///
/// Callers should treat this as the canonical defensive-copy helper for
/// `PluginConfig.config` and `ServiceSettings.config`. Closes the
/// config-map-leak bug class found by bug-hunt iters 3, 10, 11, 15, and 16.
Map<String, dynamic> _deepCopyJsonMap(Map<String, dynamic> source) {
  if (source.isEmpty) return const {};
  return <String, dynamic>{
    for (final entry in source.entries)
      entry.key: _deepCopyJsonValue(entry.value),
  };
}

dynamic _deepCopyJsonValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _deepCopyJsonMap(value);
  }
  if (value is List) {
    return [for (final v in value) _deepCopyJsonValue(v)];
  }
  return value;
}

/// Policy for handling [RuntimeSettings] entries that reference an id
/// the runtime does not know about. Covers every reference shape that
/// can drift across app versions:
///
/// - a plugin id key in [RuntimeSettings.plugins] for a plugin that is
///   no longer registered,
/// - the plugin portion of a service pin in [RuntimeSettings.services]
///   when the named plugin is no longer registered, and
/// - the service-id portion of a pin when the named plugin exists but
///   no longer registers a service under that id.
///
/// Cached user settings frequently survive across app upgrades that
/// rename or remove ids; the policy decides whether to fail loud,
/// degrade gracefully with a log, or silently drop the unknown entry.
///
/// Used by [PluginRuntime.init] (and the matching `init`-style entry
/// points) to gate every validation pass.
///
/// The default is [throwError]: the base package stays strict until a
/// caller explicitly opts into a softer policy. Production apps that
/// load cached settings across app upgrades should typically use
/// [logAndSkip] (or [ignore], if drift is surfaced by another channel).
enum UnknownReferencePolicy {
  /// Throw [StateError] on the first unknown reference. The default.
  /// Surfaces typos and renamed ids loudly in development and CI.
  /// Not safe for production load paths that read cached user
  /// settings, since a renamed plugin or service in storage would
  /// crash app startup; switch to [logAndSkip] for those callsites.
  throwError,

  /// Log severe and drop the unknown entry. Recommended for
  /// production load paths that read cached settings written by a
  /// prior app version. The configuration partial-applies: known
  /// entries take effect, unknown ones are skipped. A single severe
  /// log entry per apply call summarises the dropped ids so
  /// developers still see drift when logging is wired up.
  logAndSkip,

  /// Silently drop the unknown entry. Use only when another channel
  /// (UI surfacing of sanitised settings, a structured drift signal)
  /// already informs the user about the drop.
  ignore,
}

/// Configuration for a single service slot within a plugin.
///
/// Controls whether the service is enabled, the per-service configuration
/// values injected via [ConfigNode], and an optional priority override that
/// changes resolution order.
///
/// In [RuntimeSettings.services], entries are keyed as `"pluginId:serviceId"`
/// for plugin-scoped overrides, or `"*:serviceId"` for wildcard
/// (winner-scoped) overrides.
///
/// ```json
/// {
///   "enabled": true,
///   "config": {
///     "provider": "anthropic",
///     "model": "claude-sonnet-4-5-20250929"
///   },
///   "priority": 200
/// }
/// ```
class ServiceSettings {
  /// Whether this service is enabled. When false, the registry emits a
  /// [LocalPluginOverride.disable] which skips the service during resolution.
  final bool enabled;

  /// Service-specific configuration injected into the service via
  /// [PluginService.injectSettings] when it is resolved.
  final Map<String, dynamic> config;

  /// Optional priority override. When set, replaces the priority the plugin
  /// used at registration time. Higher priorities win during resolution.
  /// `null` means use the registration default.
  final int? priority;

  /// Creates service settings.
  const ServiceSettings({
    this.enabled = true,
    this.config = const {},
    this.priority,
  });

  /// Creates service settings from a JSON map. The parsed `config` map is
  /// deep-copied so later mutations to the source JSON cannot reach in.
  factory ServiceSettings.fromJson(Map<String, dynamic> json) {
    return ServiceSettings(
      enabled: json['enabled'] as bool? ?? true,
      config: _deepCopyJsonMap(
        json['config'] as Map<String, dynamic>? ?? const {},
      ),
      priority: (json['priority'] as num?)?.toInt(),
    );
  }

  /// Converts these service settings to JSON. The emitted `config` map is
  /// a deep copy so mutations to the result cannot reach back into the
  /// settings instance.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'config': _deepCopyJsonMap(config),
    if (priority != null) 'priority': priority,
  };

  /// Returns a copy with any provided fields replaced. The `config` map of
  /// the result is detached from both the caller and the source instance.
  ///
  /// `copyWith(priority: null)` is a known Dart-language limitation: optional
  /// parameters cannot distinguish "argument omitted" from "argument passed
  /// as null", so passing `priority: null` here keeps the existing priority
  /// rather than clearing it. To explicitly clear an `int?` field, use the
  /// dedicated sister method [withClearedPriority]. Do NOT replace this with
  /// a sentinel-based `Object? priority` overload, that pattern weakens the
  /// public API's compile-time type safety in exchange for one rare case.
  // #docregion settings-copy-with
  ServiceSettings copyWith({
    bool? enabled,
    Map<String, dynamic>? config,
    int? priority,
  }) {
    return ServiceSettings(
      enabled: enabled ?? this.enabled,
      config: _deepCopyJsonMap(config ?? this.config),
      priority: priority ?? this.priority,
    );
  }
  // #enddocregion settings-copy-with

  /// Returns a copy with [priority] set to `null` (clearing any priority
  /// override). Sister method to [copyWith]: the latter cannot clear a
  /// nullable field via `copyWith(priority: null)` (Dart language
  /// limitation, not a bug). Combine with [copyWith] when you need to clear
  /// priority AND change other fields: `s.copyWith(enabled: false).withClearedPriority()`.
  ServiceSettings withClearedPriority() {
    return ServiceSettings(
      enabled: enabled,
      config: _deepCopyJsonMap(config),
      priority: null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is ServiceSettings &&
        enabled == other.enabled &&
        const DeepCollectionEquality().equals(config, other.config) &&
        priority == other.priority;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    const DeepCollectionEquality().hash(config),
    priority,
  );

  @override
  String toString() =>
      'ServiceSettings(enabled: $enabled, config: $config, priority: $priority)';
}

/// Plugin-level configuration including enable/disable state.
///
/// Controls whether a plugin as a whole is on, plus any plugin-wide
/// configuration that isn't service-specific.
///
/// ```json
/// {
///   "enabled": true,
///   "config": {
///     "api_key": "sk-..."
///   }
/// }
/// ```
class PluginConfig {
  /// Whether this plugin is enabled. For plugins that are not
  /// [FeatureFlag.locked], false skips [Plugin.register], so the plugin's
  /// services are not added to that scope's registry.
  final bool enabled;

  /// Plugin-wide configuration. Unlike [ServiceSettings.config] which is
  /// scoped to one service, this applies to plugin-level concerns such as API
  /// keys or global feature toggles.
  final Map<String, dynamic> config;

  /// Creates plugin-level configuration.
  const PluginConfig({this.enabled = true, this.config = const {}});

  /// Creates plugin config from a JSON map. The parsed `config` map is
  /// deep-copied so later mutations to the source JSON cannot reach in.
  factory PluginConfig.fromJson(Map<String, dynamic> json) {
    return PluginConfig(
      enabled: json['enabled'] as bool? ?? true,
      config: _deepCopyJsonMap(
        json['config'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }

  /// Converts this plugin config to JSON. The emitted `config` map is a
  /// deep copy so mutations to the result cannot reach back in.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'config': _deepCopyJsonMap(config),
  };

  /// Returns a copy with any provided fields replaced. The `config` map of
  /// the result is detached from both the caller and the source instance.
  PluginConfig copyWith({bool? enabled, Map<String, dynamic>? config}) {
    return PluginConfig(
      enabled: enabled ?? this.enabled,
      config: _deepCopyJsonMap(config ?? this.config),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is PluginConfig &&
        enabled == other.enabled &&
        const DeepCollectionEquality().equals(config, other.config);
  }

  @override
  int get hashCode =>
      Object.hash(enabled, const DeepCollectionEquality().hash(config));

  @override
  String toString() => 'PluginConfig(enabled: $enabled, config: $config)';
}

/// Top-level serializable configuration for the plugin system.
///
/// Single source of truth for plugin and service configuration. Serializable
/// to and from JSON, passed to [PluginRuntime.init] and
/// [PluginRuntime.createSession], streamed via
/// [PluginRuntime.settingsStream].
///
/// [plugins] is keyed by `pluginId`. [services] is keyed by [Pin],
/// an extension type over the wire key string. The JSON wire form for each key
/// is `"pluginId:serviceId"` (or `"*:serviceId"` for wildcard). See
/// [Pin.wire] and [Pin.fromWire].
///
/// ```json
/// {
///   "plugins": {
///     "core": {"enabled": true},
///     "firebase_mcp": {"enabled": false}
///   },
///   "services": {
///     "agentic:main_agent.agent_service": {
///       "config": {"provider": "anthropic", "model": "claude-sonnet-4-5-20250929"}
///     },
///     "*:main_agent.temperature": {
///       "config": {"value": 0.7}
///     }
///   }
/// }
/// ```
class RuntimeSettings {
  /// Plugin-level configurations keyed by plugin id.
  final Map<PluginId, PluginConfig> plugins;

  /// Service-level configurations keyed by [Pin]. The wire form
  /// of each key (used in JSON serialization) is `"pluginId:serviceId"`
  /// or `"*:serviceId"`. See [Pin.wire] and
  /// [Pin.fromWire].
  final Map<Pin, ServiceSettings> services;

  /// Creates runtime settings with optional plugin and service maps.
  const RuntimeSettings({this.plugins = const {}, this.services = const {}});

  /// Creates runtime settings from a JSON map.
  factory RuntimeSettings.fromJson(Map<String, dynamic> json) {
    return RuntimeSettings(
      plugins:
          (json['plugins'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
              PluginId(k),
              PluginConfig.fromJson(e as Map<String, dynamic>),
            ),
          ) ??
          const {},
      services:
          (json['services'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(
              Pin.fromWire(k),
              ServiceSettings.fromJson(e as Map<String, dynamic>),
            ),
          ) ??
          const {},
    );
  }

  /// Converts these runtime settings to JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'plugins': {
      for (final entry in plugins.entries) entry.key: entry.value.toJson(),
    },
    'services': {
      for (final entry in services.entries) entry.key: entry.value.toJson(),
    },
  };

  /// Whether [pluginId] is enabled, per the explicit settings value alone.
  ///
  /// Returns the explicit [PluginConfig.enabled] value if one exists in
  /// [plugins], otherwise `true`. This is the settings-intent answer:
  /// it does NOT consult feature flags, the experimental-aware default,
  /// or dependency-cascade results. For base runtime enablement
  /// (locked plugins, explicit config, experimental fallback), use
  /// [PluginRuntime.isPluginEnabled]. For the post-cascade runtime
  /// truth, use [PluginRuntime.isPluginAttached].
  bool isPluginEnabled(PluginId pluginId) {
    final config = plugins[pluginId];
    if (config != null) {
      return config.enabled;
    }

    return true;
  }

  /// Whether the service identified by [scopedKey] is enabled. Services
  /// default to enabled when no settings entry exists for them.
  bool isServiceEnabled(Pin scopedKey) {
    final config = services[scopedKey];
    return config?.enabled ?? true;
  }

  /// Configuration map for the service identified by [scopedKey], or an
  /// empty map. Returns a deep copy so callers cannot mutate the stored
  /// settings via the returned map.
  Map<String, dynamic> getServiceConfig(Pin scopedKey) {
    final config = services[scopedKey];
    if (config == null) return const {};
    return _deepCopyJsonMap(config.config);
  }

  /// Configuration map for [pluginId], or an empty map. Returns a deep
  /// copy so callers cannot mutate the stored settings via the returned
  /// map.
  Map<String, dynamic> getPluginConfig(PluginId pluginId) {
    final config = plugins[pluginId];
    if (config == null) return const {};
    return _deepCopyJsonMap(config.config);
  }

  /// Returns a copy with optional plugin/service map replacements. Both
  /// the top-level maps AND the nested [PluginConfig] / [ServiceSettings]
  /// values are detached: mutating the result (or any of its `config`
  /// maps) cannot reach back into the source snapshot.
  // #docregion settings-copy-with-2
  RuntimeSettings copyWith({
    Map<PluginId, PluginConfig>? plugins,
    Map<Pin, ServiceSettings>? services,
  }) {
    // #enddocregion settings-copy-with-2
    return RuntimeSettings(
      plugins: {
        for (final entry in (plugins ?? this.plugins).entries)
          entry.key: entry.value.copyWith(),
      },
      services: {
        for (final entry in (services ?? this.services).entries)
          entry.key: entry.value.copyWith(),
      },
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is RuntimeSettings &&
        const MapEquality<PluginId, PluginConfig>().equals(
          plugins,
          other.plugins,
        ) &&
        const MapEquality<Pin, ServiceSettings>().equals(
          services,
          other.services,
        );
  }

  @override
  int get hashCode => Object.hash(
    const MapEquality<PluginId, PluginConfig>().hash(plugins),
    const MapEquality<Pin, ServiceSettings>().hash(services),
  );

  @override
  String toString() =>
      'RuntimeSettings(plugins: $plugins, services: $services)';
}
