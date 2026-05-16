import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Locked Flutter-side plugin that supplies host-app overrides for the
/// dialog's visual surfaces. Supports three registration axes: plugin rows
/// keyed by pluginId, namespace section headers keyed by [Namespace], and
/// service cards keyed by [ServiceId].
///
/// Carries [FeatureFlag.locked] because it is host-app infrastructure: the
/// user does not toggle it from the dialog.
///
/// Conflict semantics: this plugin registers above the default priority used
/// when a Flutter plugin self-attaches its own visuals from its own
/// `register()`. Two host plugins decorating the same key resolve via
/// standard registry priority; pass distinct [pluginId]s to make ownership
/// traceable in the registry inspector.
///
/// Unknown keys (a [PluginId], [Namespace], or [ServiceId] that no plugin
/// currently registers) are accepted silently. The visual is retained so
/// enabling the plugin later picks it up automatically - and a key for an
/// installed-but-disabled plugin is indistinguishable from a typo at attach
/// time, so reporting one would over-fire on the other. Resolve at the
/// consumption site if you need to detect leftover config.
///
/// ```dart
/// runtime
///   ..addPlugins(myPlugins())
///   ..addPlugin(PluginKitVisualsPlugin(
///     pluginVisuals: const {
///       PluginId('main_agent'): PluginKitVisual(
///         label: 'Main Agent',
///         icon: Icon(Icons.psychology),
///         color: Color(0xFF7C5CFF),
///       ),
///     },
///   ));
/// ```
class PluginKitVisualsPlugin extends GlobalPlugin {
  /// Namespace for the new unified plugin-axis visuals
  /// (`PluginKitVisual` keyed by `pluginId`).
  static const Namespace pluginVisualNamespace = Namespace('plugin_visual');

  /// Namespace for namespace-axis visuals (`PluginKitVisual` keyed by
  /// `Namespace`, which `implements String`).
  static const Namespace namespaceVisualNamespace = Namespace(
    'namespace_visual',
  );

  /// Namespace for service-axis visuals (`PluginKitVisual` keyed by
  /// `ServiceId`, which `implements String`).
  static const Namespace serviceVisualNamespace = Namespace('service_visual');

  /// [ServiceId] for the plugin-axis visual keyed by [pluginId]. Use as the
  /// argument to `registry.maybeResolve<PluginKitVisual>(...)` when looking
  /// up the visual override for a specific plugin.
  static ServiceId visualFor(PluginId pluginId) =>
      pluginVisualNamespace(pluginId);

  /// [ServiceId] for the namespace-axis visual keyed by [namespace]. Use as
  /// the argument to `registry.maybeResolve<PluginKitVisual>(...)` when
  /// looking up the visual override for a namespace section header.
  static ServiceId visualOf(Namespace namespace) =>
      namespaceVisualNamespace(namespace);

  /// [ServiceId] for the service-axis visual keyed by [serviceId]. Use as
  /// the argument to `registry.maybeResolve<PluginKitVisual>(...)` when
  /// looking up the visual override for a specific service card.
  static ServiceId visualOfService(ServiceId serviceId) =>
      serviceVisualNamespace(serviceId);

  /// Registration priority used so host overrides beat self-attached
  /// visuals registered at the default registry priority
  /// ([Priority.normal]). Sits at the [Priority.elevated] band: the
  /// conventional "I am an override" stop.
  static const int dialogVisualsAdapterPriority = Priority.elevated;

  /// Stable plugin id for registry lookup.
  static const id = PluginId('plugin_kit_visuals');

  @override
  final PluginId pluginId = id;

  /// Plugin-axis visuals. Keyed by [PluginId].
  final Map<PluginId, PluginKitVisual> pluginVisuals;

  /// Namespace-axis visuals. Keyed by [Namespace].
  final Map<Namespace, PluginKitVisual> namespaceVisuals;

  /// Service-axis visuals (root or namespaced). Keyed by [ServiceId].
  final Map<ServiceId, PluginKitVisual> serviceVisuals;

  /// Three-axis constructor. Input maps mirror the spec.
  PluginKitVisualsPlugin({
    this.pluginVisuals = const {},
    this.namespaceVisuals = const {},
    this.serviceVisuals = const {},
  });

  @override
  List<FeatureFlag> get featureFlags => const [.locked];

  @override
  void register(ScopedServiceRegistry registry) {
    for (final MapEntry(key: pid, value: visual) in pluginVisuals.entries) {
      registry.registerSingleton<PluginKitVisual>(
        visualFor(pid),
        () => visual,
        priority: dialogVisualsAdapterPriority,
      );
    }
    for (final MapEntry(key: ns, value: visual) in namespaceVisuals.entries) {
      registry.registerSingleton<PluginKitVisual>(
        visualOf(ns),
        () => visual,
        priority: dialogVisualsAdapterPriority,
      );
    }
    for (final MapEntry(key: svc, value: visual) in serviceVisuals.entries) {
      registry.registerSingleton<PluginKitVisual>(
        visualOfService(svc),
        () => visual,
        priority: dialogVisualsAdapterPriority,
      );
    }
  }
}

/// Default [PluginChipsBuilder] registered by `PluginsTabPlugin`.
///
/// Iterates `runtime.plugins`, merges any registered [PluginKitVisual]
/// overrides over the derived defaults, partitions by
/// [FeatureFlag.experimental], and resolves [PluginChipModel.isEnabled]
/// against [settings] using the precedence documented on
/// [PluginChipModel.isEnabled].
class PluginChipsBuilder {
  /// Creates the default builder.
  const PluginChipsBuilder();

  /// Builds the grouped chip models for the Plugins tab.
  PluginChipGroups build(PluginRuntime runtime, RuntimeSettings settings) {
    final all = _buildModels(runtime, settings);
    final stable = all
        .where((chip) => !chip.experimental)
        .toList(growable: false);
    final experimental = all
        .where((chip) => chip.experimental)
        .toList(growable: false);
    return PluginChipGroups(
      all: all,
      stable: stable,
      experimental: experimental,
    );
  }

  static List<PluginChipModel> _buildModels(
    PluginRuntime runtime,
    RuntimeSettings settings,
  ) {
    final registry = runtime.globalRegistry;
    final List<PluginChipModel> models = [];

    for (final plugin in runtime.plugins) {
      final visuals = registry.maybeResolve<PluginKitVisual>(
        PluginKitVisualsPlugin.visualFor(plugin.pluginId),
      );
      final locked = plugin.featureFlags.contains(FeatureFlag.locked);
      final defaultEnabled = PluginRuntime.isPluginEnabledByDefault(plugin);
      final isEnabled = runtime.isPluginEnabled(plugin.pluginId, settings);
      models.add(
        PluginChipModel(
          pluginId: plugin.pluginId,
          label: visuals?.label ?? plugin.pluginId,
          description: visuals?.description,
          icon: visuals?.icon,
          color: visuals?.color,
          experimental: plugin.featureFlags.contains(FeatureFlag.experimental),
          locked: locked,
          defaultEnabled: defaultEnabled,
          isEnabled: isEnabled,
        ),
      );
    }
    return List.unmodifiable(models);
  }
}

/// Unified visuals descriptor used for all three axes of the dialog: plugin
/// rows, namespace section headers, and service cards. Same value object,
/// different maps in [PluginKitVisualsPlugin].
///
/// All fields are optional; the dialog falls back to derived defaults
/// (raw `pluginId` / namespace name / service id; theme primary color) for
/// any field left null. The accent color follows a service to namespace to
/// owning-plugin to theme cascade resolved by the dialog at render time.
class PluginKitVisual {
  /// Display label override. When null, the dialog uses a derived default.
  final String? label;

  /// Optional descriptive text shown in detail surfaces.
  final String? description;

  /// Optional leading widget. Wrapped by the dialog in an `IconTheme` keyed
  /// to the resolved accent color and a default size, so a plain
  /// `Icon(Icons.X)` inherits the chrome automatically.
  final Widget? icon;

  /// Optional accent color. Cascade resolves to the namespace's color, then
  /// the owning plugin's color, then the theme primary when null.
  final Color? color;

  /// Creates a unified visual descriptor.
  const PluginKitVisual({this.label, this.description, this.icon, this.color});
}

/// Resolved view-model for one plugin row.
///
/// Layered: [PluginKitVisual] overrides win over derived defaults
/// (`label = raw pluginId`, `description = null`, no icon, no accent).
/// Pure data; recompute per build.
class PluginChipModel {
  /// Stable runtime plugin identifier.
  final PluginId pluginId;

  /// Resolved label (override or raw `pluginId`).
  final String label;

  /// Resolved description override, if any.
  final String? description;

  /// Override icon widget, if any. Wrapped in an [IconTheme] by the chip
  /// renderer so a plain `Icon(Icons.X)` inherits accent + size.
  final Widget? icon;

  /// Override accent color, if any.
  final Color? color;

  /// Whether the plugin carries the `experimental` feature flag.
  final bool experimental;

  /// Whether the plugin carries the `locked` feature flag.
  final bool locked;

  /// Whether the plugin is enabled by default per
  /// [PluginRuntime.isPluginEnabledByDefault].
  final bool defaultEnabled;

  /// Whether the plugin is currently enabled, resolved against the
  /// [RuntimeSettings] passed to [PluginChipsBuilder.build]. Resolution
  /// order: locked plugins are always enabled, then any explicit
  /// `settings.plugins[pluginId].enabled` override, then [defaultEnabled].
  final bool isEnabled;

  /// Creates a resolved plugin row model.
  const PluginChipModel({
    required this.pluginId,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.experimental,
    required this.locked,
    required this.defaultEnabled,
    required this.isEnabled,
  });
}

/// Partitioned view of [PluginChipModel]s with per-partition enabled counts.
///
/// Built by a registered [PluginChipsBuilder] so call sites that want both
/// stable/experimental partitioning and section counts can avoid iterating
/// the chip list multiple times.
class PluginChipGroups {
  /// Every chip the runtime exposes, in `runtime.plugins` order.
  final List<PluginChipModel> all;

  /// Subset of [all] without [FeatureFlag.experimental].
  final List<PluginChipModel> stable;

  /// Subset of [all] with [FeatureFlag.experimental].
  final List<PluginChipModel> experimental;

  /// Creates a partitioned chip-groups view.
  PluginChipGroups({
    required this.all,
    required this.stable,
    required this.experimental,
  }) : enabledCount = _countEnabled(all),
       stableEnabledCount = _countEnabled(stable),
       experimentalEnabledCount = _countEnabled(experimental);

  /// Count of currently-enabled chips across [all].
  final int enabledCount;

  /// Count of currently-enabled chips in [stable].
  final int stableEnabledCount;

  /// Count of currently-enabled chips in [experimental].
  final int experimentalEnabledCount;

  static int _countEnabled(Iterable<PluginChipModel> chips) =>
      chips.where((chip) => chip.isEnabled).length;
}
