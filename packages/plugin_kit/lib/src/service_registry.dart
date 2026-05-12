import 'package:collection/collection.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Factory function that constructs a service instance.
///
/// Called on every [ServiceRegistry.resolve] for [FactoryWrapper]
/// registrations, or once for [LazySingletonWrapper] registrations.
typedef Factory<T> = T Function();

/// A set of [Capability] tags attached to a service registration.
///
/// Capabilities enable metadata discovery without instantiating the service.
/// Define custom [Capability] subclasses to describe whatever facts about a
/// slot the host app cares about (supported formats, priority hints, audit
/// flags, etc.) and read them via [RegistrationWrapper.capabilities] without
/// ever calling [RegistrationWrapper.provide].
// #docregion service-registry-capability-set
typedef CapabilitySet = Set<Capability>;
// #enddocregion service-registry-capability-set

/// Sealed base class for service registration wrappers.
///
/// Every service registered in the [ServiceRegistry] is stored as a
/// `RegistrationWrapper`. The sealed hierarchy defines three instantiation
/// strategies: [FactoryWrapper] creates a new instance on every [provide],
/// [LazySingletonWrapper] creates on first [provide] and caches thereafter,
/// and [SingletonWrapper] holds a pre-created instance and always returns it.
///
/// Wrappers also carry [pluginId] (owner), [priority] (resolution order, with
/// higher winning), and [capabilities] for discovery via custom [Capability]
/// subclasses. Equality is based on [pluginId] and [priority].
sealed class RegistrationWrapper<T extends Object> {
  /// The plugin that owns this registration.
  final PluginId pluginId;

  /// Backing for [priority]. Library-private; mutated only via
  /// [_setEffectivePriority] from [ServiceRegistry.updateSettings] (and
  /// from registration-time stamping inside the same library). Public
  /// callers see the read-only [priority] getter.
  int _priority;

  /// Resolution priority. Higher values win when multiple plugins register
  /// the same service id. Default is [ServiceRegistry.defaultPriority].
  ///
  /// This is the *effective* priority used for sort and resolution. It is
  /// equal to [basePriority] until a [LocalPluginOverride] with a
  /// non-null [LocalPluginOverride.priority] is applied via
  /// [ServiceRegistry.updateSettings]; it is reverted to [basePriority]
  /// when that override goes away.
  ///
  /// Read-only at the public surface. The registry itself owns mutation.
  int get priority => _priority;

  /// The priority this wrapper was originally registered with — i.e.,
  /// the value passed to `registerFactory` / `registerSingleton` /
  /// `registerLazySingleton`. Independent of any override applied later.
  final int basePriority;

  /// Metadata capabilities attached to this registration.
  final CapabilitySet capabilities;

  RegistrationWrapper(
    this.pluginId, {
    int priority = ServiceRegistry.defaultPriority,
    this.capabilities = const {},
  }) : _priority = priority,
       basePriority = priority;

  /// Create or return the service instance.
  T provide();

  /// Deep-clone this wrapper for [ServiceRegistry.copy]. The clone shares
  /// the underlying instance / factory / settings, but has independent
  /// mutable [priority] storage so post-copy [_setEffectivePriority]
  /// calls on the live registry do not leak into the snapshot.
  RegistrationWrapper<T> _clone();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is RegistrationWrapper &&
        pluginId == other.pluginId &&
        basePriority == other.basePriority;
  }

  @override
  int get hashCode => Object.hash(pluginId, basePriority);

  @override
  String toString() =>
      '$runtimeType(pluginId: $pluginId, priority: $priority, base: $basePriority)';
}

/// Library-private accessor for [RegistrationWrapper._priority]. Restricted
/// to in-library callers (the registry's `updateSettings` and the
/// register-time stamping calls).
extension _WrapperMutation<T extends Object> on RegistrationWrapper<T> {
  void _setEffectivePriority(int value) => _priority = value;
}

/// Registration wrapper that creates a new instance on every [provide] call.
///
/// Use for services that should not share state between consumers, or that
/// are cheap to construct.
final class FactoryWrapper<T extends Object> extends RegistrationWrapper<T> {
  /// The factory function called on each [provide].
  final Factory<T> factory;

  /// Creates a factory wrapper for [pluginId] using [factory].
  FactoryWrapper(
    super.pluginId,
    this.factory, {
    super.priority,
    super.capabilities,
  });

  @override
  T provide() => factory();

  @override
  FactoryWrapper<T> _clone() {
    final c = FactoryWrapper<T>(
      pluginId,
      factory,
      priority: basePriority,
      capabilities: capabilities,
    );
    c._setEffectivePriority(_priority);
    return c;
  }
}

/// Registration wrapper that creates the instance on first [provide] call
/// and caches it for all subsequent calls.
///
/// Use for services that are expensive to construct but safe to share.
final class LazySingletonWrapper<T extends Object>
    extends RegistrationWrapper<T> {
  /// The factory function called once on first [provide].
  final Factory<T> factory;

  /// Explicit init state. Tracks whether [factory] has run so callers can
  /// distinguish "instance not yet constructed" from "instance constructed
  /// to null" without forcing construction via `_instance`. Reentry of
  /// [provide] during initialization is rejected by Dart's `late final`
  /// cyclic-init detection on `_instance`.
  bool _initialized = false;
  late final T _instance = () {
    final r = factory();
    _initialized = true;
    return r;
  }();

  /// Creates a lazy singleton wrapper for [pluginId] using [factory].
  LazySingletonWrapper(
    super.pluginId,
    this.factory, {
    super.priority,
    super.capabilities,
  });

  @override
  T provide() => _instance;

  /// The cached instance if [provide] has already been called and the
  /// factory completed, otherwise `null`. Lets the registry decide whether
  /// a re-registration would strand a live instance.
  T? get instanceIfCreated => _initialized ? _instance : null;

  @override
  LazySingletonWrapper<T> _clone() {
    final c = LazySingletonWrapper<T>(
      pluginId,
      factory,
      priority: basePriority,
      capabilities: capabilities,
    );
    c._setEffectivePriority(_priority);
    return c;
  }
}

/// Registration wrapper that holds a pre-created instance.
///
/// The [object] is provided at registration time and returned on every
/// [provide] call. Use for services that must be created eagerly or that are
/// provided from outside the plugin system.
final class SingletonWrapper<T extends Object> extends RegistrationWrapper<T> {
  /// The pre-created singleton instance.
  final T object;

  /// Creates a singleton wrapper for [pluginId] with [object].
  SingletonWrapper(
    super.pluginId,
    this.object, {
    super.priority,
    super.capabilities,
  });

  @override
  T provide() => object;

  @override
  SingletonWrapper<T> _clone() {
    final c = SingletonWrapper<T>(
      pluginId,
      object,
      priority: basePriority,
      capabilities: capabilities,
    );
    c._setEffectivePriority(_priority);
    return c;
  }
}

/// Dependency injection container for plugin services.
///
/// `ServiceRegistry` is the central service locator in the plugin system.
/// Plugins register their services during the `register*` lifecycle phase,
/// and other plugins (or the runtime) resolve them by service id.
///
/// ## Registration
///
/// Services are registered with one of three strategies:
/// - [registerFactory]: New instance on every resolve.
/// - [registerLazySingleton]: Created once on first resolve, cached after.
/// - [registerSingleton]: Eagerly-created instance, always reused.
///
/// Each registration carries a [pluginId] (owner), `serviceId` (slot),
/// [priority] (resolution order), and optional [CapabilitySet] (metadata).
///
/// Namespacing is a property of the [ServiceId] itself, not of the registry
/// API: build a namespaced id with `Namespace.call(...)` (`ns('id')`),
/// [Namespace.service], or [ServiceId.namespaced] and pass it to the regular
/// `register*` and `resolve*` methods.
///
/// ## Resolution
///
/// Resolution selects the highest-priority registration for a given service
/// id. The candidate list is pre-sorted by priority (descending); the first
/// enabled entry wins. [RegistrationWrapper.provide] then creates or returns
/// the instance. If the instance is a [PluginService], scoped settings from
/// [overrides] are injected via [PluginService.injectSettings].
///
/// Resolution methods:
/// - [resolve]: Returns the winner or throws [StateError].
/// - [maybeResolve]: Returns the winner or `null`.
/// - [resolveAfter]: Chain-of-responsibility, skipping past a specific plugin.
/// - [resolveRaw]: Returns the [RegistrationWrapper] itself, no instantiation.
///
/// ## Settings injection
///
/// When resolving a [PluginService], the registry checks [overrides] for
/// matching [LocalPluginOverride] entries (by service id and plugin id, with
/// fallback to [PluginId.winnerScoped] for wildcard overrides). Matching settings are
/// injected via [PluginService.injectSettings]. For singleton/lazy services,
/// a hash comparison avoids redundant updates.
///
/// ## Override system
///
/// [overrides] is a list of [LocalPluginOverride] entries that can disable a
/// service (`enabled: false`), change its priority, or inject settings.
/// Overrides are parsed from [RuntimeSettings.services] by the
/// [PluginRuntime] during session preparation.
///
/// ```dart
/// final registry = ServiceRegistry();
///
/// registry.registerFactory<MyService>(
///   pluginId: const PluginId('my_plugin'),
///   serviceId: const ServiceId('my_service'),
///   create: () => MyServiceImpl(),
///   priority: 100,
/// );
///
/// final service = registry.resolve<MyService>(const ServiceId('my_service'));
/// ```
class ServiceRegistry {
  /// Default resolution priority used by every registration method when
  /// `priority` is not supplied. Higher values win; [Priority.normal]
  /// sits mid-stack so later plugins can boost (via [Priority.elevated],
  /// [Priority.high], or [Priority.above]) or lower relative to it.
  static const int defaultPriority = Priority.normal;

  /// Active overrides for settings injection, priority changes, and disabling.
  ///
  /// Updated by [updateSettings] when [RuntimeSettings] change. Access via
  /// [overrides] (read-only view) or modify via [updateSettings].
  List<LocalPluginOverride> _overrides;

  /// Internal storage: service id -> sorted list of registrations. Each list
  /// is sorted by priority (descending); the first enabled entry is the
  /// winner returned by [resolve].
  final Map<ServiceId, List<RegistrationWrapper>> _registry;

  /// Read-only view of the current overrides.
  List<LocalPluginOverride> get overrides => List.unmodifiable(_overrides);

  /// Sorted list of registrations for [serviceId], or `null` when none exist.
  ///
  /// Read access without instantiation or settings injection. Useful for
  /// inspecting all registrants for a slot, not just the winner.
  List<RegistrationWrapper>? getRegistrations(ServiceId serviceId) {
    final list = _registry[serviceId];
    if (list == null) return null;
    return List.unmodifiable(list);
  }

  /// Registrations for [serviceId] filtered to wrappers of type [T].
  List<RegistrationWrapper<T>>? getRegistrationsOfType<T extends Object>(
    ServiceId serviceId,
  ) {
    final list = _registry[serviceId];
    if (list == null) return null;
    return List.unmodifiable(list.whereType<RegistrationWrapper<T>>());
  }

  /// Creates a registry with optional initial [overrides].
  ServiceRegistry({List<LocalPluginOverride> overrides = const []})
    : _overrides = overrides,
      _registry = {};

  /// Creates an empty registry with no overrides.
  ServiceRegistry.empty() : _overrides = [], _registry = {};

  ServiceRegistry._from({
    required Map<ServiceId, List<RegistrationWrapper>> registry,
    required List<LocalPluginOverride> overrides,
  }) : _registry = registry,
       _overrides = overrides;

  /// Creates a shallow copy of this registry.
  ///
  /// The registration lists are copied (not the wrappers themselves), and
  /// overrides are copied by value. Used by [PluginContext.copyWith] to
  /// snapshot the registry state.
  /// Snapshot the current registry state.
  ///
  /// Both the per-service lists AND the wrappers themselves are cloned,
  /// so `priority` mutations applied by [updateSettings] on the live
  /// registry afterwards do NOT leak into the snapshot. This isolation
  /// is what makes `oldContext` (passed to
  /// [Plugin.onPluginSettingsChanged]) compare reliably against
  /// `newContext`: each context owns its own wrapper instances.
  ServiceRegistry copy() => ServiceRegistry._from(
    registry: {
      for (final entry in _registry.entries)
        entry.key: [for (final wrapper in entry.value) wrapper._clone()],
    },
    overrides: [..._overrides],
  );

  /// Replace the current overrides and re-sort affected registration
  /// lists.
  ///
  /// Called by the [PluginRuntime] after parsing new [RuntimeSettings].
  /// Plugin-specific priority overrides are applied retroactively: every
  /// existing wrapper has its effective [RegistrationWrapper.priority]
  /// recomputed from the new overrides (falling back to
  /// [RegistrationWrapper.basePriority] when no priority override applies).
  /// Only lists whose wrappers actually saw an effective-priority change
  /// are re-sorted - identical-overrides reconciliations skip the sort
  /// entirely, which keeps the operation cheap on runtimes with many
  /// registered services.
  ///
  /// Wildcard (`*`) priority overrides are forwarded to whichever plugin
  /// currently wins the slot at the time the override resolves. The
  /// [PluginRuntime] computes those forwarded priority overrides via
  /// `_resolveAndApplyWildcards` and feeds them in alongside the
  /// plugin-specific overrides; this method then restamps the winning
  /// wrapper's effective `priority` and re-sorts. The forwarding is
  /// winner-scoped, not layered: only the current winner's wrapper sees a
  /// wildcard priority bump on each settings update.
  void updateSettings({required List<LocalPluginOverride> overrides}) {
    final wasEmpty = _overrides.isEmpty;
    _overrides = overrides;
    // Short-circuit: when neither the previous nor the new override list
    // can affect any wrapper's effective priority, there is no work to
    // do. This handles the very common "reconcile with no overrides"
    // path that otherwise iterates every registered wrapper for no
    // benefit.
    if (wasEmpty && overrides.isEmpty) return;

    for (final MapEntry(key: serviceId, value: list) in _registry.entries) {
      bool changed = false;

      for (final wrapper in list) {
        final newPriority = _effectivePriorityFor(serviceId, wrapper);
        if (wrapper.priority != newPriority) {
          wrapper._setEffectivePriority(newPriority);
          changed = true;
        }
      }
      if (changed) {
        list.sort((a, b) => b.priority.compareTo(a.priority));
      }
    }
  }

  /// Compute the effective priority for [wrapper] under [serviceId] given
  /// the current [_overrides]. Used by both [updateSettings] (to restamp
  /// existing wrappers) and the registration paths (to seed a new wrapper
  /// with the priority that current settings dictate).
  ///
  /// Plugin-specific priority overrides win; otherwise falls back to
  /// [RegistrationWrapper.basePriority].
  int _effectivePriorityFor(ServiceId serviceId, RegistrationWrapper wrapper) {
    for (final override in _overrides) {
      if (override.priority case final priority?
          when override.serviceId == serviceId &&
              override.plugin == wrapper.pluginId) {
        return priority;
      }
    }
    return wrapper.basePriority;
  }

  /// Returns the [LocalPluginOverride] to use for injecting settings into
  /// the service registered by [wrapper] for [serviceId].
  ///
  /// Prefers a plugin-specific override, then falls back to a winner-scoped
  /// ([PluginId.winnerScoped]) override.
  LocalPluginOverride? _overrideForInjection(
    ServiceId serviceId,
    RegistrationWrapper wrapper,
  ) {
    final pluginOverride = _overrides
        .where((o) => o.serviceId == serviceId && o.plugin == wrapper.pluginId)
        .firstOrNull;
    if (pluginOverride != null) return pluginOverride;
    return _overrides
        .where(
          (o) => o.serviceId == serviceId && o.plugin == PluginId.winnerScoped,
        )
        .firstOrNull;
  }

  /// Whether [wrapper] is marked disabled by an active override.
  ///
  /// Resolution methods skip disabled wrappers and fall through to the
  /// next-highest-priority enabled registration. A plugin-specific override
  /// takes precedence over a wildcard (`*`) one, matching the semantics of
  /// [_overrideForInjection]. If the matching override exists but leaves
  /// `enabled: true`, the wrapper is considered live.
  bool _isDisabled(ServiceId serviceId, RegistrationWrapper wrapper) {
    final override = _overrideForInjection(serviceId, wrapper);
    return override != null && !override.enabled;
  }

  /// Return the first wrapper in [list] that isn't disabled by an override,
  /// or `null` if every candidate is disabled.
  RegistrationWrapper? _firstEnabled(
    ServiceId serviceId,
    List<RegistrationWrapper> list,
  ) {
    for (final wrapper in list) {
      if (!_isDisabled(serviceId, wrapper)) return wrapper;
    }
    return null;
  }

  /// Instantiate a service from a [RegistrationWrapper] and inject any
  /// applicable settings from [_overrides].
  ///
  /// Single point of truth for the provide-then-inject pattern; all
  /// resolution methods delegate here.
  T _provideAndInject<T>(ServiceId serviceId, RegistrationWrapper wrapper) {
    final service = wrapper.provide();

    if (service is PluginService) {
      // Stamp the authoritative identity onto the service. This is the
      // single place where [PluginService.pluginId] and
      // [PluginService.serviceId] become trustworthy: as "the plugin
      // that owns me" and "my full key in the registry": regardless of how
      // the subclass was constructed. Every resolve path flows through here,
      // so the stamp happens before any consumer sees the instance.
      service.pluginId = wrapper.pluginId;
      service.serviceId = serviceId;

      final override = _overrideForInjection(serviceId, wrapper);
      if (override != null && override.settings.isNotEmpty) {
        if (wrapper is SingletonWrapper || wrapper is LazySingletonWrapper) {
          final oldHash = service.settingsHash;
          final newHash = ConfigNode.hashSettings(override.settings);
          if (oldHash != newHash) {
            service.injectSettings(override.settings, hash: newHash);
          }
        } else {
          service.injectSettings(override.settings);
        }
      }
    }

    return service as T;
  }

  /// Resolve the highest-priority service for [serviceId].
  ///
  /// If the resolved instance is a [PluginService], scoped settings from
  /// [_overrides] are injected automatically.
  ///
  /// Throws [StateError] if no service is registered for [serviceId], or if
  /// every registration for [serviceId] has been disabled via a
  /// [LocalPluginOverride].
  T resolve<T>(ServiceId serviceId) {
    final list =
        _registry[serviceId] ??
        (throw StateError('No service registered for "$serviceId"'));
    final wrapper = _firstEnabled(serviceId, list);
    if (wrapper == null) {
      throw StateError(
        'All registrations for "$serviceId" are disabled by overrides '
        '(candidates: ${list.map((w) => w.pluginId).join(", ")})',
      );
    }
    return _provideAndInject<T>(serviceId, wrapper);
  }

  /// Resolve the next service in priority order after [pluginId].
  ///
  /// Implements a chain-of-responsibility pattern: finds the registration
  /// owned by [pluginId], then returns the next one in the sorted list. This
  /// allows a higher-priority plugin to delegate to the service it overrode.
  /// Settings injection is applied to the resolved service just as in
  /// [resolve].
  ///
  /// The caller's own enabled state (i.e. whether [pluginId]'s registration
  /// is disabled by an override) is not consulted; the target is located by
  /// id only. The walk past the target skips any disabled registrations and
  /// returns the first enabled wrapper. If no enabled wrapper exists after
  /// the target, this throws, distinguishing "no later registration" from
  /// "every later registration is disabled" in the error message.
  ///
  /// Throws [StateError] if [serviceId] has no registrations, if [pluginId]
  /// is not found, or if every registration after [pluginId] is either
  /// absent or disabled.
  // #docregion service-registry-resolve-after
  T resolveAfter<T>({
    required PluginId pluginId,
    required ServiceId serviceId,
  }) {
    // #enddocregion service-registry-resolve-after
    final list =
        _registry[serviceId] ??
        (throw StateError('No service registered for "$serviceId"'));

    int targetIndex = 0;
    while (list[targetIndex].pluginId != pluginId) {
      targetIndex++;
      if (targetIndex >= list.length) {
        throw StateError(
          'No service registered for "$serviceId" after plugin "$pluginId"',
        );
      }
    }

    final afterTarget = list.sublist(targetIndex + 1);
    if (afterTarget.isEmpty) {
      throw StateError(
        'No service registered for "$serviceId" after plugin "$pluginId"',
      );
    }
    for (final wrapper in afterTarget) {
      if (_isDisabled(serviceId, wrapper)) continue;
      return _provideAndInject<T>(serviceId, wrapper);
    }
    throw StateError(
      'All registrations for "$serviceId" after plugin "$pluginId" '
      'are disabled by overrides (candidates: '
      '${afterTarget.map((w) => w.pluginId).join(", ")})',
    );
  }

  /// Resolve the raw [RegistrationWrapper] for [serviceId] without
  /// instantiating or injecting settings.
  ///
  /// Useful for inspecting registration metadata ([pluginId], [priority],
  /// [capabilities]) without side effects. Disabled registrations are
  /// skipped, matching [resolve] semantics.
  ///
  /// Throws [StateError] if no service is registered for [serviceId], or if
  /// every registration for [serviceId] has been disabled by a
  /// [LocalPluginOverride].
  RegistrationWrapper<T> resolveRaw<T extends Object>(ServiceId serviceId) {
    final list =
        _registry[serviceId] ??
        (throw StateError('No service registered for "$serviceId"'));

    final wrapper = _firstEnabled(serviceId, list);
    if (wrapper == null) {
      throw StateError(
        'All registrations for "$serviceId" are disabled by overrides '
        '(candidates: ${list.map((w) => w.pluginId).join(", ")})',
      );
    }
    return wrapper as RegistrationWrapper<T>;
  }

  /// Resolve the highest-priority enabled service, or `null` if none.
  ///
  /// Same as [resolve] but returns `null` instead of throwing when no service
  /// is registered for [serviceId] or when every registration has been
  /// disabled by a [LocalPluginOverride].
  T? maybeResolve<T extends Object>(ServiceId serviceId) {
    final list = _registry[serviceId];
    if (list == null || list.isEmpty) return null;
    final wrapper = _firstEnabled(serviceId, list);
    if (wrapper == null) return null;
    return _provideAndInject<T>(serviceId, wrapper);
  }

  /// Like [resolveRaw] but returns `null` if no service is registered or
  /// every registration is disabled by an override.
  RegistrationWrapper? maybeResolveRaw<T extends Object>(ServiceId serviceId) {
    final list = _registry[serviceId];
    if (list == null || list.isEmpty) return null;
    final wrapper = _firstEnabled(serviceId, list);
    if (wrapper == null) return null;
    return wrapper as RegistrationWrapper<T>;
  }

  /// Returns the [Capability] of type [C] attached to the winning
  /// registration for [serviceId], or `null` if the service is not
  /// registered, every registration is disabled, or the winner does not
  /// carry a capability of that type.
  ///
  /// Use the non-null return both as a presence check and to read the
  /// capability's fields:
  ///
  /// ```dart
  /// final formats = registry.resolveCapability<SupportsFileFormats>(
  ///   const ServiceId('importer'),
  /// );
  /// if (formats != null && formats.extensions.contains('md')) {
  ///   // ...
  /// }
  /// ```
  ///
  /// No service instance is constructed.
  C? resolveCapability<C extends Capability>(ServiceId serviceId) {
    final list = _registry[serviceId];
    if (list == null || list.isEmpty) return null;
    final wrapper = _firstEnabled(serviceId, list);
    if (wrapper == null) return null;
    return wrapper.capabilities.getOfType<C>();
  }

  /// Get all instantiated services registered by [plugin].
  ///
  /// Iterates all service ids, finds registrations owned by [plugin],
  /// creates instances via [_provideAndInject], and returns them. Used by
  /// [Plugin.attach] and [Plugin.detach] to find [StatefulPluginService]s.
  ///
  /// When [skipFactories] is true, only singleton and lazy-singleton
  /// registrations are instantiated. This avoids creating throwaway
  /// instances from factory registrations when the caller only needs cached
  /// services (e.g. [StatefulPluginService]s for lifecycle management).
  /// Defaults to false.
  List<Object> getPluginServices(
    PluginId plugin, {
    bool skipFactories = false,
  }) {
    final services = <Object>[];
    for (final entry in _registry.entries) {
      final serviceId = entry.key;
      for (final wrapper in entry.value) {
        if (wrapper.pluginId != plugin) continue;
        if (skipFactories && wrapper is FactoryWrapper) continue;
        services.add(_provideAndInject<Object>(serviceId, wrapper));
      }
    }
    return services;
  }

  /// Register a factory service that creates a new instance on every resolve.
  ///
  /// If a registration from the same [pluginId] already exists for
  /// [serviceId], it is replaced. The [priority] may be overridden by a
  /// matching [LocalPluginOverride] in [overrides]. The registration list is
  /// re-sorted after insertion.
  void registerFactory<T extends Object>({
    required PluginId pluginId,
    required ServiceId serviceId,
    required Factory<T> create,
    int priority = ServiceRegistry.defaultPriority,
    CapabilitySet capabilities = const {},
  }) {
    // StatefulPluginService instances must be registered as a singleton or
    // lazy singleton so the runtime can manage their lifecycle. Factories
    // are not tracked and would leak orphan instances. The list-of-T
    // covariance idiom is the canonical way to ask "is T a subtype of X"
    // without an instance in hand.
    if (<T>[] is List<StatefulPluginService>) {
      throw ArgumentError(
        'StatefulPluginService "$serviceId" must be registered as a '
        'singleton or lazy singleton, not a factory. '
        'They require proper lifecycle management which factories do not provide.',
      );
    }

    _rejectIfAttachedStatefulReplacement(
      list: _registry[serviceId],
      pluginId: pluginId,
      serviceId: serviceId,
    );

    final wrapper = FactoryWrapper<T>(
      pluginId,
      create,
      priority: priority,
      capabilities: capabilities,
    );
    wrapper._setEffectivePriority(_effectivePriorityFor(serviceId, wrapper));

    // Only mutate the registry after validation and wrapper construction
    // succeed, so a thrown guard or factory does not leave an empty bucket
    // that pollutes listAllServiceIds() and changes resolve()'s error
    // shape from "not registered" to "all disabled".
    final list = _registry[serviceId] ??= [];
    list
      ..removeWhere((wrapper) => wrapper.pluginId == pluginId)
      ..add(wrapper)
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Rejects a `register*` call that would replace an existing
  /// `StatefulPluginService` whose `attach` has already run for some
  /// `PluginContext`. The replaced wrapper would be dropped while its old
  /// instance still owns subscriptions on the bus and still has its
  /// `_context` bound, and the new instance would never receive an
  /// `attach()` call from `_runAttach` (the per-plugin attach pass has
  /// already completed).
  ///
  /// Allowed: replacement of a non-stateful service, or a stateful
  /// instance that was never attached (no bound context).
  ///
  /// To swap a live stateful service, disable then re-enable the owning
  /// plugin via `RuntimeSettings`; the framework's settings reconciliation
  /// detaches and re-attaches cleanly.
  void _rejectIfAttachedStatefulReplacement({
    required List<RegistrationWrapper>? list,
    required PluginId pluginId,
    required ServiceId serviceId,
  }) {
    if (list == null) return;
    final existing = list.firstWhereOrNull((w) => w.pluginId == pluginId);
    if (existing == null) return;
    final Object? instance;
    switch (existing) {
      case SingletonWrapper(:final object):
        instance = object;
      case LazySingletonWrapper():
        instance = existing.instanceIfCreated;
      case FactoryWrapper():
        // Factories cannot hold StatefulPluginService instances (rejected
        // at registerFactory time); nothing to strand.
        instance = null;
    }
    if (instance is StatefulPluginService && instance.hasContext) {
      throw ArgumentError(
        'Cannot replace registration "$serviceId" for plugin "$pluginId": '
        'the existing StatefulPluginService is attached. Replacing it '
        'would strand the old instance (subscriptions and context stay '
        'bound) and leave the new instance without an attach() call, '
        'because _runAttach has already completed for this plugin. '
        'Disable then re-enable the owning plugin via RuntimeSettings to '
        'swap a live stateful service.',
      );
    }
  }

  /// Register an eager singleton service via a [Factory] that constructs
  /// the instance.
  ///
  /// The factory runs ONCE at registration time. The resulting instance is
  /// stored in a [SingletonWrapper] and returned on every resolve. Use an
  /// inline expression to get a fresh instance per `register()` call:
  ///
  /// ```dart
  /// registry.registerSingleton<MyService>(
  ///   pluginId: pluginId,
  ///   serviceId: serviceId,
  ///   create: () => MyService(),
  /// );
  /// ```
  ///
  /// For SessionPlugins, `register()` runs per session, so each session gets
  /// its own instance. To share an instance across sessions, the factory
  /// must visibly close over a long-lived value (e.g. `() => _shared`); the
  /// closure capture is the discriminator at the call site.
  ///
  /// Contrast with [registerFactory] (factory runs on every resolve) and
  /// [registerLazySingleton] (factory runs once on first resolve, not at
  /// registration). Replaces any existing registration from the same
  /// [pluginId].
  // #docregion service-registry-register-singleton
  void registerSingleton<T extends Object>({
    required PluginId pluginId,
    required ServiceId serviceId,
    required Factory<T> create,
    int priority = ServiceRegistry.defaultPriority,
    CapabilitySet capabilities = const {},
  }) {
    // #enddocregion service-registry-register-singleton
    _rejectIfAttachedStatefulReplacement(
      list: _registry[serviceId],
      pluginId: pluginId,
      serviceId: serviceId,
    );

    // Defer instance construction until after the replacement guard so a
    // rejected re-registration does not run the factory and leak side
    // effects.
    final instance = create();

    final wrapper = SingletonWrapper<T>(
      pluginId,
      instance,
      priority: priority,
      capabilities: capabilities,
    );
    wrapper._setEffectivePriority(_effectivePriorityFor(serviceId, wrapper));

    // Only mutate the registry after validation and wrapper construction
    // succeed, so a thrown guard or factory does not leave an empty bucket.
    final list = _registry[serviceId] ??= [];
    list
      ..removeWhere((wrapper) => wrapper.pluginId == pluginId)
      ..add(wrapper)
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Register a lazy singleton that is created on first resolve and cached.
  ///
  /// Replaces any existing registration from the same [pluginId].
  void registerLazySingleton<T extends Object>({
    required PluginId pluginId,
    required ServiceId serviceId,
    required Factory<T> factory,
    int priority = ServiceRegistry.defaultPriority,
    CapabilitySet capabilities = const {},
  }) {
    _rejectIfAttachedStatefulReplacement(
      list: _registry[serviceId],
      pluginId: pluginId,
      serviceId: serviceId,
    );

    final wrapper = LazySingletonWrapper<T>(
      pluginId,
      factory,
      priority: priority,
      capabilities: capabilities,
    );
    wrapper._setEffectivePriority(_effectivePriorityFor(serviceId, wrapper));

    // Only mutate the registry after validation and wrapper construction
    // succeed, so a thrown guard does not leave an empty bucket.
    final list = _registry[serviceId] ??= [];
    list
      ..removeWhere((wrapper) => wrapper.pluginId == pluginId)
      ..add(wrapper)
      ..sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Returns a plugin-scoped view that fills in [pluginId] on every
  /// registration call, so plugins don't have to repeat it.
  ScopedServiceRegistry scopedFor(PluginId pluginId) =>
      ScopedServiceRegistry(this, pluginId);

  /// Remove a specific plugin's registration for [serviceId].
  ///
  /// Returns the removed [RegistrationWrapper], or `null` if no registration
  /// was found. If the removal empties the list for [serviceId], the entire
  /// key is removed from the registry. Used during settings reconciliation
  /// to unregister services from disabled plugins.
  // #docregion service-registry-unregister
  RegistrationWrapper? unregister({
    required PluginId pluginId,
    required ServiceId serviceId,
  }) {
    // #enddocregion service-registry-unregister
    final list = _registry[serviceId];
    if (list == null) return null;

    final wrapper = list.firstWhereOrNull(
      (wrapper) => wrapper.pluginId == pluginId,
    );
    list.remove(wrapper);
    if (list.isEmpty) {
      _registry.remove(serviceId);
    }

    return wrapper;
  }

  /// The winning [RegistrationWrapper] for every registered service id, with
  /// no instantiation.
  ///
  /// One entry per service id (the highest-priority enabled wrapper, matching
  /// [resolveRaw] semantics). For the resolved instances, use
  /// [listAllServices] which calls [resolve] on each.
  Map<ServiceId, RegistrationWrapper> getAllResolvedRegistrations() => {
    for (final serviceId in _registry.keys) serviceId: resolveRaw(serviceId),
  };

  /// Whether any service from [pluginId] is registered.
  ///
  /// Only checks service registrations; plugins that only register tools
  /// won't be detected here.
  bool didPluginRegisterServices(PluginId pluginId) => _registry.values.any(
    (wrappers) => wrappers.any((wrapper) => wrapper.pluginId == pluginId),
  );

  /// List all service ids, optionally filtered to a specific [pluginId].
  ///
  /// When [pluginId] is null, returns all registered service ids. When
  /// provided, returns only ids that have a registration from that plugin.
  Set<ServiceId> listAllServiceIds([PluginId? pluginId]) {
    if (pluginId == null) return _registry.keys.toSet();

    return {
      for (final entry in _registry.entries)
        for (final wrapper in entry.value)
          if (wrapper.pluginId == pluginId) entry.key,
    };
  }

  /// Resolve all registered services, returning service id to instance.
  ///
  /// Each service is resolved (instantiated and settings-injected) via
  /// [resolve].
  Map<ServiceId, Object> listAllServices() => {
    for (final serviceId in _registry.keys) serviceId: resolve(serviceId),
  };

  /// Collect all [Capability] tags from services within a namespace.
  ///
  /// Scans all service ids whose [ServiceId.value] starts with
  /// `'${namespace.value}.'` and aggregates their
  /// [RegistrationWrapper.capabilities]. Nested namespaces are matched too:
  /// a query for `Namespace('agent')` includes services like
  /// `'agent.system_prompt.scope'`.
  CapabilitySet listCapabilitiesOfNamespace(Namespace namespace) {
    final capabilities = <Capability>{};
    final prefix = '${namespace.value}.';
    for (final entry in _registry.entries) {
      if (!entry.key.value.startsWith(prefix)) continue;

      for (final wrapper in entry.value) {
        capabilities.addAll(wrapper.capabilities);
      }
    }
    return capabilities;
  }
}

/// Per-service override that modifies registration behavior.
///
/// `LocalPluginOverride` entries are created by the [PluginRuntime] when
/// parsing [RuntimeSettings.services] and stored in
/// [ServiceRegistry.overrides]. They can disable a service, change its
/// priority, or inject settings.
///
/// Overrides are matched by `(plugin, serviceId)` pair. The special
/// [PluginId.winnerScoped] value for [plugin] indicates a wildcard (winner-scoped)
/// override that applies to whichever plugin wins the resolution.
///
/// ```dart
/// LocalPluginOverride.disable(
///   plugin: PluginId('agentic'),
///   serviceId: ServiceId('main_agent.tools'),
/// );
///
/// LocalPluginOverride.withPriority(
///   plugin: PluginId('core'),
///   serviceId: ServiceId('main_agent.agent_service'),
///   priority: 200,
/// );
///
/// LocalPluginOverride(
///   plugin: PluginId('agentic'),
///   serviceId: ServiceId('main_agent.agent_service'),
///   settings: {'provider': 'anthropic', 'model': 'claude-sonnet-4-5-20250929'},
/// );
/// ```
class LocalPluginOverride {
  /// The plugin id this override targets, or [PluginId.winnerScoped] for wildcards.
  final PluginId plugin;

  /// The service id this override applies to.
  final ServiceId serviceId;

  /// Whether the service is enabled. When false, the service is skipped
  /// during resolution.
  final bool enabled;

  /// Optional priority override. When non-null, replaces the registration's
  /// original priority during [ServiceRegistry.registerFactory] and variants.
  final int? priority;

  /// Settings to inject into the service via [PluginService.injectSettings].
  final Map<String, dynamic> settings;

  /// Creates a service override for [plugin] and [serviceId].
  const LocalPluginOverride({
    required this.plugin,
    required this.serviceId,
    this.enabled = true,
    this.priority,
    this.settings = const {},
  });

  /// Convenience constructor to disable a service.
  const LocalPluginOverride.disable({
    required this.plugin,
    required this.serviceId,
  }) : enabled = false,
       priority = null,
       settings = const {};

  /// Convenience constructor to override a service's priority.
  const LocalPluginOverride.withPriority({
    required this.plugin,
    required this.serviceId,
    required this.priority,
  }) : enabled = true,
       settings = const {};

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is LocalPluginOverride &&
        plugin == other.plugin &&
        serviceId == other.serviceId &&
        enabled == other.enabled &&
        priority == other.priority &&
        const DeepCollectionEquality().equals(settings, other.settings);
  }

  @override
  int get hashCode => Object.hash(
    plugin,
    serviceId,
    enabled,
    priority,
    const DeepCollectionEquality().hash(settings),
  );

  @override
  String toString() =>
      'LocalPluginOverride(plugin: $plugin, serviceId: $serviceId, '
      'enabled: $enabled, priority: $priority, settings: $settings)';
}

/// A plugin-scoped view over [ServiceRegistry] that fills in the owning
/// plugin's `pluginId` on every registration call.
///
/// Plugins receive one of these in their [Plugin.register] override, so the
/// `pluginId` argument is never passed explicitly:
///
/// ```dart
/// @override
/// void register(ScopedServiceRegistry registry) {
///   registry.registerSingleton<MyService>(
///     const ServiceId('my_service'),
///     MyServiceImpl(),
///   );
/// }
/// ```
///
/// To register many services under the same namespace, build each
/// [ServiceId] inline with `Namespace.call`: a namespace const reads as a
/// composition primitive, e.g. `agent('model')` and `agent('temperature')`.
///
/// Edge cases that need the full registry (registering on behalf of another
/// plugin, inspecting existing registrations, etc.) can reach through via
/// [raw].
class ScopedServiceRegistry {
  /// The underlying registry. Use this for operations that aren't tied to
  /// the owning plugin (cross-plugin queries, etc.).
  // #docregion service-registry-final
  final ServiceRegistry raw;

  // #enddocregion service-registry-final

  /// The plugin id this scope belongs to. Every registration call below
  /// forwards this as the `pluginId` argument.
  final PluginId pluginId;

  /// Default priority applied by the positional `register*` overloads when
  /// their `priority` argument is omitted. Set via [withPriority].
  /// Null means fall back to [ServiceRegistry.defaultPriority].
  final int? defaultPriority;

  /// Creates a plugin-scoped registry view over [raw] for [pluginId].
  const ScopedServiceRegistry(this.raw, this.pluginId, {this.defaultPriority});

  /// Returns a copy of this scope that applies [priority] as the default for
  /// any positional `register*` cascade entry that omits its own `priority`.
  /// Per-call `priority` always wins.
  ScopedServiceRegistry withPriority(int priority) =>
      ScopedServiceRegistry(raw, pluginId, defaultPriority: priority);

  /// Register a factory service using a typed [ServiceId] handle.
  /// Equivalent to [ServiceRegistry.registerFactory].
  void registerFactory<T extends Object>(
    ServiceId service,
    Factory<T> create, {
    int? priority,
    CapabilitySet capabilities = const {},
  }) => raw.registerFactory<T>(
    pluginId: pluginId,
    serviceId: service,
    create: create,
    priority: priority ?? defaultPriority ?? ServiceRegistry.defaultPriority,
    capabilities: capabilities,
  );

  /// Register a singleton service using a typed [ServiceId] handle.
  ///
  /// The [create] factory runs once at registration time. Use an inline
  /// expression so each `register()` call gives a fresh instance:
  ///
  /// ```dart
  /// registry.registerSingleton<MyService>(id, () => MyService());
  /// ```
  ///
  /// For session plugins, `register` runs once per session, so each session
  /// gets its own instance and there is no cross-session sharing. To share
  /// across sessions, have the factory close over a long-lived value (e.g.
  /// `() => _sharedField`); the closure capture is visible at the call
  /// site, so the choice between fresh-per-session and shared-across-sessions
  /// is explicit, not implicit.
  // #docregion service-registry-register-singleton-2
  void registerSingleton<T extends Object>(
    ServiceId service,
    Factory<T> create, {
    int? priority,
    CapabilitySet capabilities = const {},
  }) => raw.registerSingleton<T>(
    pluginId: pluginId,
    serviceId: service,
    create: create,
    priority: priority ?? defaultPriority ?? ServiceRegistry.defaultPriority,
    capabilities: capabilities,
  );

  // #enddocregion service-registry-register-singleton-2

  /// Register a lazy singleton service using a typed [ServiceId] handle.
  void registerLazySingleton<T extends Object>(
    ServiceId service,
    Factory<T> factory, {
    int? priority,
    CapabilitySet capabilities = const {},
  }) => raw.registerLazySingleton<T>(
    pluginId: pluginId,
    serviceId: service,
    factory: factory,
    priority: priority ?? defaultPriority ?? ServiceRegistry.defaultPriority,
    capabilities: capabilities,
  );
}
