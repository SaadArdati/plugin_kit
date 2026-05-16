part of '../plugin.dart';

extension _RuntimeInit<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
>
    on PluginRuntime<G, S> {
  void _addPluginImpl(Plugin plugin) {
    if (_isReservedPluginId(plugin.pluginId)) {
      throw ArgumentError.value(
        plugin.pluginId,
        'plugin.pluginId',
        'PluginId values starting with "__pk_" are reserved for internal use.',
      );
    }

    if (_plugins.any((p) => p.pluginId == plugin.pluginId)) {
      throw StateError('Plugin ${plugin.pluginId} is already registered');
    }

    _plugins.add(plugin);
  }

  void _addPluginsImpl(List<Plugin> plugins) {
    for (final plugin in plugins) {
      addPlugin(plugin);
    }
  }

  PluginRuntime _initImpl({
    RuntimeSettings? settings,
    GlobalContextFactory<G, S>? globalContextFactory,
    UnknownReferencePolicy unknownReferencePolicy =
        UnknownReferencePolicy.throwError,
  }) {
    // A disposed runtime is terminal. The supported flow is
    // construct -> init -> use -> dispose -> drop reference. Allowing a
    // second init() on a disposed runtime would resurrect closed bus and
    // settings-controller subscribers in a partly-undefined state; reject
    // loudly instead.
    if (_disposed) {
      throw StateError(
        'PluginRuntime.init() called on a disposed runtime. A runtime '
        'cannot be reinitialized after dispose; construct a new '
        'PluginRuntime instance instead.',
      );
    }
    // Defensive: if init() is called a second time without dispose() in
    // between, the previous controller is still alive and would leak when
    // we reassign the field below. Close it first. This is a programming
    // error (the documented flow is init -> use -> dispose -> init), but
    // we handle it gracefully rather than silently leaking.
    if (_initialized && !_settingsController.isClosed) {
      _settingsController.close();
    }
    _initialized = true;
    _unknownReferencePolicy = unknownReferencePolicy;
    _normalizer = SettingsNormalizer(
      policy: _unknownReferencePolicy,
      logger: _runtimeLog,
    );
    _enablement = EnablementResolver();
    _settingsController = StreamController<RuntimeSettings>.broadcast(
      sync: true,
    );
    _runtimeLog.info('Initializing runtime');

    globalBus = EventBus();

    // Pre-register normalization: defensive copy of caller maps, plus
    // plugin-id filtering. The registry has no services yet so the
    // service-id pass is deferred until after register-all completes.
    var effectiveSettings = _normalizeSettings(
      entryPoint: 'init',
      raw: settings ?? const RuntimeSettings(),
      scopePlugins: globalPlugins,
    );
    _settingsValue = effectiveSettings;

    // Parse service settings into overrides for the global registry.
    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};
    _partitionServiceSettings(
      services: effectiveSettings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: globalPlugins,
    );

    globalRegistry = ServiceRegistry(overrides: overrides);

    // Determine enabled global plugins (uses _determineEnabledPluginIds
    // which correctly handles experimental flags and dependency validation).
    _enabledGlobalPluginIds.addAll(
      _determineEnabledPluginIds(
        effectiveSettings,
        pluginSubset: globalPlugins,
      ),
    );
    _runtimeLog.fine(
      'Enabled global plugins: ${_enabledGlobalPluginIds.join(', ')}',
    );

    // Register enabled global plugins. A throwing register() is the same
    // shape of bug as a throwing attach(): without rollback, the plugin
    // id stays in `_enabledGlobalPluginIds` and any partial registrations
    // it made before throwing stay live. Collect errors and roll the
    // plugin back per-plugin.
    final registerErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        try {
          plugin.register(globalRegistry.scopedFor(plugin.pluginId));
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to register global plugin "${plugin.pluginId}"',
            e,
            st,
          );
          registerErrors.add((plugin.pluginId, e, st));
          _enabledGlobalPluginIds.remove(plugin.pluginId);
          final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
          for (final id in serviceIds) {
            globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
          }
        }
      }
    }
    // Throw register errors before pin-validation runs, so the user sees
    // the actual register failure rather than a downstream StateError
    // from validation against the rolled-back registry. Also unwind
    // siblings that registered successfully: this throw fires before
    // [globalContext] is initialized, so leaving siblings in
    // `_enabledGlobalPluginIds` would advertise them as attached
    // without ever running attach() and would LateInitializationError
    // on dispose.
    if (registerErrors.isNotEmpty) {
      for (final pluginId in _enabledGlobalPluginIds.toList()) {
        final serviceIds = globalRegistry.listAllServiceIds(pluginId);
        for (final id in serviceIds) {
          globalRegistry.unregister(pluginId: pluginId, serviceId: id);
        }
      }
      _enabledGlobalPluginIds.clear();
      _runtimeLog.warning(
        'Runtime register pass failed for ${registerErrors.length} plugin(s)',
      );
      throw PluginLifecycleException('attachGlobal', registerErrors);
    }
    // Post-register normalization: with every global plugin registered,
    // the set of known service ids per plugin is stable. Run the third
    // pass to drop service pins whose service-id is unknown to its named
    // plugin. If anything drops, rewrite `_settingsValue` and rebuild the
    // registry's overrides so the dropped entries don't survive there.
    final finalSettings = _normalizeSettings(
      entryPoint: 'init',
      raw: effectiveSettings,
      scopePlugins: globalPlugins,
      registryForServiceIdCheck: globalRegistry,
    );
    if (finalSettings.services.length != effectiveSettings.services.length) {
      effectiveSettings = finalSettings;
      _settingsValue = effectiveSettings;
      final rebuiltOverrides = <LocalPluginOverride>[];
      final rebuiltWildcards = <ServiceId, ServiceSettings>{};
      _partitionServiceSettings(
        services: effectiveSettings.services,
        overrides: rebuiltOverrides,
        pendingWildcards: rebuiltWildcards,
        plugins: globalPlugins,
      );
      // Sync both the live registry AND the local lists. The downstream
      // `_resolveAndApplyWildcards` / `globalRegistry.updateSettings` calls
      // below operate on the local `overrides` / `pendingWildcards` so we
      // must replace their contents, not just push to the registry.
      globalRegistry.updateSettings(overrides: rebuiltOverrides);
      overrides
        ..clear()
        ..addAll(rebuiltOverrides);
      pendingWildcards
        ..clear()
        ..addAll(rebuiltWildcards);
    }
    // Create global context
    if (globalContextFactory != null) {
      globalContext = globalContextFactory(
        globalRegistry,
        globalBus,
        _sessions,
      );
    } else {
      if (G != GlobalPluginContext) {
        throw StateError(
          'globalContextFactory is required when using a custom global context '
          'type ($G). The default factory creates a GlobalPluginContext, which '
          'cannot be assigned to $G.',
        );
      }
      globalContext =
          GlobalPluginContext(
                registry: globalRegistry,
                bus: globalBus,
                sessions: _sessions,
              )
              as G;
    }

    // Apply wildcard overrides and inject all settings into global services.
    _resolveAndApplyWildcards(
      registry: globalRegistry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );
    if (pendingWildcards.isEmpty && overrides.isNotEmpty) {
      globalRegistry.updateSettings(overrides: overrides);
    }

    // Attach enabled plugins. Per-plugin rollback on failure (option a):
    // a failed attach() removes the plugin from [_enabledGlobalPluginIds]
    // and unregisters its services, so attached/enabled tracking equals
    // reality. Successfully-attached siblings stay attached. Subscriptions
    // opened in attach() before the throw stay live until process exit
    // because sync init() cannot await `_unbindContext`, and dispose()
    // does not re-detach the rolled-back plugin. Option (b) async init
    // replaces this with a proper unwind; see
    // docs/superpowers/plans/2026-05-13-runtime-correctness-followups.md.
    final attachErrors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      if (_enabledGlobalPluginIds.contains(plugin.pluginId)) {
        try {
          plugin._runAttach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to attach global plugin "${plugin.pluginId}"',
            e,
            st,
          );
          attachErrors.add((plugin.pluginId, e, st));
          // Unwind the failed plugin's attach-time side effects. Without
          // this, any StatefulPluginService.attach() that subscribed to the
          // global bus before the user's plugin.attach() threw leaves its
          // subscription live. init() is sync so we can't await detach
          // here; instead, cancel each subscription's stream subscription
          // synchronously (the cancel itself is async but does NOT need to
          // be awaited for the handler to stop firing - the bus dispatcher
          // checks subscription state on each emit).
          final statefulServices = globalRegistry
              .getPluginServices(plugin.pluginId, skipFactories: true)
              .whereType<StatefulPluginService>();
          for (final service in statefulServices) {
            final subs = [...service.activeSubscriptions];
            service.activeSubscriptions.clear();
            for (final sub in subs) {
              unawaited(sub.cancel().catchError((_, _) {}));
            }
            final bindings = [...service.activeBindings];
            service.activeBindings.clear();
            for (final cancel in bindings) {
              try {
                cancel();
              } catch (_) {
                // bindings are best-effort; ignore inverse-cancel throws
              }
            }
            // Unbind the context so the service is observably not-attached.
            service._context = null;
          }
          _enabledGlobalPluginIds.remove(plugin.pluginId);
          final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
          for (final id in serviceIds) {
            globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
          }
        }
      }
    }

    if (attachErrors.isNotEmpty) {
      _runtimeLog.warning(
        'Runtime initialized with ${attachErrors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('attachGlobal', attachErrors);
    }
    _runtimeLog.info('Runtime initialized');

    return this;
  }
}
