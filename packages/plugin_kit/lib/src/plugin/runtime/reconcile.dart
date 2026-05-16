part of '../plugin.dart';

/// Transactional reconcile cluster for PluginRuntime.
///
/// Holds the entire settings-update transaction: updateSettings, both
/// updateGlobalSettings paths, both updateSessionSettings paths, the
/// per-session enablement rollback (_revertSessionEnablement), plugin
/// reconcile (_reconcilePluginsOnSettingsUpdate), service-lifecycle diff
/// (_reconcileServiceLifecycleDiff), and the attached-stateful-services
/// pre-snapshot (_snapshotAttachedStatefulServices). The _reconciling
/// guard and _enterReconcile stay on PluginRuntime (state, not behavior);
/// this extension reads/writes them directly since it shares the library.
///
/// Three public methods (updateSettings, updateGlobalSettings,
/// updateSessionSettings) remain as one-line forwarders on PluginRuntime
/// per the public-API immutability rule; their bodies live here as
/// *Impl methods on this extension.
extension _RuntimeReconcile<
  G extends GlobalPluginContext,
  S extends SessionPluginContext
>
    on PluginRuntime<G, S> {
  /// Update session settings with full reconciliation.
  ///
  /// Applies [newSettings] and determines which plugins need to be enabled,
  /// disabled, or notified of changes:
  ///
  /// 1. Parse new service settings into overrides.
  /// 2. Reconcile plugin enablement (disable/detach or enable/register/attach).
  /// 3. Apply wildcard overrides.
  /// 4. Update the registry's override list.
  /// 5. Notify remaining enabled plugins via [Plugin.onPluginSettingsChanged].
  Future<void> _updateSessionSettingsImpl(
    PluginSession<S> session, {
    required RuntimeSettings newSettings,
  }) async {
    if (!_initialized || _disposed) {
      throw StateError(
        'PluginRuntime.updateSessionSettings() called ${_disposed ? 'on a disposed runtime' : 'before init()'}. '
        'Call init() first.',
      );
    }
    // Reject sessions owned by another runtime. Without this guard the
    // caller can corrupt a foreign runtime's session state because the
    // reconcile path mutates `session._enabledPluginIds` and the
    // session's registry overrides using THIS runtime's plugin set.
    if (!_sessions.contains(session)) {
      throw StateError(
        'PluginRuntime.updateSessionSettings() called with a session not '
        'owned by this runtime. Sessions can only be reconfigured by the '
        'runtime that created them.',
      );
    }
    _enterReconcile('updateSessionSettings');
    try {
      _validateServiceSettingPluginIds(
        entryPoint: 'updateSessionSettings',
        services: newSettings.services,
      );
      _validatePluginConfigPluginIds(
        entryPoint: 'updateSessionSettings',
        plugins: newSettings.plugins,
      );
      await _updateSessionSettingsInternal(session, newSettings: newSettings);
      _sessionSettings[session] = newSettings;
    } finally {
      _reconciling = false;
    }
  }

  /// Body of [updateSessionSettings] without the re-entry guard. Used by
  /// [updateSettings] which already holds the guard for the whole pass.

  /// Body of [updateSessionSettings] without the re-entry guard. Used by
  /// [updateSettings] which already holds the guard for the whole pass.
  Future<void> _updateSessionSettingsInternal(
    PluginSession<S> session, {
    required RuntimeSettings newSettings,
  }) async {
    // Snapshot the session's enabled set BEFORE any reconcile work so a
    // throwing post-flip step (notify hook) can roll back to exactly the
    // state the session had on entry.
    final preUpdateEnabled = Set<PluginId>.from(session.enabledPluginIds);
    final oldContext = session.context.copyWith();
    // Strict runtimeType equality is intentionally over-constrained for now:
    // the bug we're guarding against only requires `oldContext` to be
    // assignable to whatever the plugin's covariant `onPluginSettingsChanged`
    // declares. If the framework ever grows "context promotion" semantics
    // (subclass on snapshot, base type on live, or vice versa), weaken this
    // to an `is`-check that matches the plugin's declared type.
    assert(
      oldContext.runtimeType == session.context.runtimeType,
      'Custom context subclass ${session.context.runtimeType} did not override '
      'copyWith(); onPluginSettingsChanged will receive a base-type oldContext '
      'and any covariant subtype override on the plugin will throw TypeError. '
      'See concepts/custom-context for the required override shape.',
    );

    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};
    _partitionServiceSettings(
      services: newSettings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: sessionPlugins,
    );

    final enabledPluginIds = _determineEnabledPluginIds(
      newSettings,
      pluginSubset: sessionPlugins,
      additionalEnabledPluginIds: _enabledGlobalPluginIds,
    );

    final registry = session.registry;
    final preUpdateOverrides = <LocalPluginOverride>[...registry.overrides];
    await _reconcilePluginsOnSettingsUpdate(
      registry: registry,
      enabledPluginIds: enabledPluginIds,
      overrides: overrides,
      session: session,
    );
    _runtimeLog.info('Session settings updated');

    // Validate service pin service ids after reconciliation: any plugins
    // newly enabled by this pass have registered, so the registry now
    // reflects every service id that should be addressable.
    _validateServicePinServiceIds(
      entryPoint: 'updateSessionSettings',
      registry: registry,
      services: newSettings.services,
      plugins: sessionPlugins,
    );

    // Snapshot attached stateful services BEFORE the override flip below
    // (which can be triggered by either _resolveAndApplyWildcards or the
    // unconditional registry.updateSettings call). The post-flip diff
    // detaches services that just flipped to disabled and attaches those
    // that flipped to enabled.
    final preAttached = _snapshotAttachedStatefulServices(
      registry: registry,
      pluginIds: enabledPluginIds,
    );

    _resolveAndApplyWildcards(
      registry: registry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );

    registry.updateSettings(overrides: overrides);

    final serviceErrors = await _reconcileServiceLifecycleDiff(
      registry: registry,
      pluginIds: enabledPluginIds,
      preAttached: preAttached,
      context: session.context,
    );

    // Notify each plugin that settings have been updated. If any plugin's
    // hook throws, roll back the session's enablement flip so the session
    // ends up in the same state it started in. Without this rollback, a
    // notify-hook throw leaves the session with the post-flip enabled set
    // even though the entire update is supposed to be transactional.
    for (final pluginId in enabledPluginIds) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
      if (plugin == null) continue;
      try {
        await plugin.onPluginSettingsChanged(oldContext, session.context);
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        registry.updateSettings(overrides: preUpdateOverrides);
        await _revertSessionEnablement(
          session: session,
          targetEnabled: preUpdateEnabled,
          currentEnabled: session.enabledPluginIds.toSet(),
          context: session.context,
        );
        await _reconcileServiceLifecycleDiff(
          registry: registry,
          pluginIds: preUpdateEnabled,
          preAttached: _snapshotAttachedStatefulServices(
            registry: registry,
            pluginIds: preUpdateEnabled,
          ),
          context: session.context,
        );
        _runtimeLog.severe(
          'Plugin "$pluginId" onPluginSettingsChanged threw; session '
          'enablement reverted to pre-update state',
          e,
          st,
        );
        rethrow;
      }
    }

    if (serviceErrors.isNotEmpty) {
      throw PluginLifecycleException('updateSessionSettings', serviceErrors);
    }
  }

  /// Reverts `session._enabledPluginIds` to [targetEnabled], running
  /// detach for plugins that need to be disabled and attach for plugins
  /// that need to be re-enabled. Used by [_updateSessionSettingsInternal]
  /// when a post-flip step (notify hook) throws.

  /// Reverts `session._enabledPluginIds` to [targetEnabled], running
  /// detach for plugins that need to be disabled and attach for plugins
  /// that need to be re-enabled. Used by [_updateSessionSettingsInternal]
  /// when a post-flip step (notify hook) throws.
  Future<void> _revertSessionEnablement({
    required PluginSession<S> session,
    required Set<PluginId> targetEnabled,
    required Set<PluginId> currentEnabled,
    required SessionPluginContext context,
  }) async {
    final toDisable = currentEnabled.difference(targetEnabled);
    final toEnable = targetEnabled.difference(currentEnabled);

    for (final pid in toDisable) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pid);
      if (plugin == null) continue;
      try {
        await plugin._runDetach(context);
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _runtimeLog.severe(
          'Revert: failed to detach plugin "$pid" during session enablement rollback',
          e,
          st,
        );
      }
      session.markPluginDisabled(pid);
    }

    for (final pid in toEnable) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pid);
      if (plugin == null) continue;
      try {
        plugin._runAttach(context);
        session.markPluginEnabled(pid);
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _runtimeLog.severe(
          'Revert: failed to re-attach plugin "$pid" during session enablement rollback',
          e,
          st,
        );
      }
    }
  }

  // ---- Helpers ----
  //
  // Service settings pipeline
  //
  // RuntimeSettings.services maps scoped keys to ServiceSettings. Each scoped
  // key is either plugin-specific ('pluginA:agent.model', targets pluginA's
  // agent.model registration) or wildcard ('*:agent.model', targets whoever
  // wins agent.model right now).
  //
  // Pipeline (run on init, createSession, and updateSettings):
  //
  //   1. Partition. _partitionServiceSettings splits the input into a
  //      finished LocalPluginOverride list (plugin-specific entries) and a
  //      pendingWildcards map (wildcards that cannot be materialized yet
  //      because the winner is not known until plugins register).
  //
  //   2. Seed. ServiceRegistry(overrides: ...) installs the finished list
  //      immediately. Plugin-specific priority overrides take effect when
  //      the matching plugin calls one of the register methods, because the
  //      registry's effectivePriority lookup only checks overrides keyed by
  //      the registering plugin's id, with no fallback
  //      to PluginId.winnerScoped.
  //
  //   3. Resolve. After plugins have registered, _resolveAndApplyWildcards
  //      looks up the current winner for each pending wildcard and emits
  //      the override under two scopes: the winner's pluginId AND
  //      PluginId.winnerScoped ('*'). Both are then passed into
  //      ServiceRegistry.updateSettings, which restamps each existing
  //      wrapper's effective priority using the new override list. So a
  //      wildcard priority intent applies live to the just-registered
  //      winner's wrapper, AND survives a future re-registration of the
  //      same plugin (e.g. a model swap that calls registerSingleton
  //      again) because the override entry stays in the registry's
  //      override list. The PluginId.winnerScoped entry separately feeds
  //      _overrideForInjection's fallback when service CONFIG settings
  //      are injected.
  //
  //   4. Lookup. The two paths that consume the override list are
  //      asymmetric. The register methods (_effectivePriorityFor) consult
  //      overrides keyed by the registering plugin's id only, with no
  //      fallback (so they pick up the wildcard-forwarded plugin-scoped
  //      entry but not the winnerScoped sentinel). _overrideForInjection
  //      merges plugin-specific with the winnerScoped fallback knob by
  //      knob: enabled AND-merges (either layer disables -> disabled),
  //      priority is plugin-specific-wins-if-set, settings is
  //      plugin-specific-wins-if-non-empty. The net effect: a wildcard's
  //      CONFIG intent persists across winner changes via the
  //      winnerScoped fallback even when a plugin-specific entry sets
  //      only priority, while its PRIORITY intent attaches to whoever
  //      was the winner at stage 3 and stays attached to that plugin's
  //      wrapper across re-registrations (priority transfers are not
  //      automatic on winner changes).

  /// Splits service settings into plugin-specific overrides (appended to
  /// [overrides] immediately) and wildcard entries (stashed in
  /// [pendingWildcards] for [_resolveAndApplyWildcards] once plugins
  /// register). See stage 1 of the pipeline narrative above.
  ///
  /// Plugin-specific keys that target plugins outside [plugins] are ignored
  /// by this pass. This lets global and session reconciliation read the same
  /// root [RuntimeSettings.services] map without failing on cross-scope keys.

  /// Reconciles plugin enablement on settings update.
  Future<void> _reconcilePluginsOnSettingsUpdate({
    required ServiceRegistry registry,
    required Set<PluginId> enabledPluginIds,
    required List<LocalPluginOverride> overrides,
    required PluginSession<S> session,
  }) async {
    final errors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in sessionPlugins) {
      final bool isEnabled = enabledPluginIds.contains(plugin.pluginId);
      final bool wasEnabled = session.isPluginEnabled(plugin.pluginId);

      if (wasEnabled && !isEnabled) {
        session.markPluginDisabled(plugin.pluginId);
        _runtimeLog.info(
          'Settings update: disabling plugin "${plugin.pluginId}"',
        );
        // Run the plugin's own detach first so any subscriptions it set up
        // in attach (and any StatefulPluginServices it owns) are torn
        // down symmetrically. The registry snapshot is taken AFTER detach
        // (matching the global path) in case detach mutates registrations.
        try {
          await plugin._runDetach(session.context);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to detach plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
        }
        final serviceIds = registry.listAllServiceIds(plugin.pluginId);
        for (final serviceId in serviceIds) {
          registry.unregister(pluginId: plugin.pluginId, serviceId: serviceId);
        }
      } else if (!wasEnabled && isEnabled) {
        _runtimeLog.info(
          'Settings update: enabling plugin "${plugin.pluginId}"',
        );
        // Wrap register in the same try/catch as attach/detach so a
        // throwing plugin doesn't abort reconciliation for other plugins.
        try {
          plugin.register(registry.scopedFor(plugin.pluginId));
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to register plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          continue;
        }
        // Calling the plugin's attach runs any direct subscriptions AND,
        // via the base implementation, attaches all StatefulPluginServices
        // the plugin just registered.
        try {
          plugin._runAttach(session.context);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to attach plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          // Cleanup pass: `_runAttach` may have bound StatefulPluginService
          // contexts and registered subscriptions before throwing. Without
          // an explicit detach, those services keep `hasContext == true`
          // and their attach-time subscriptions stay live on the bus,
          // firing for events on a "rolled back" plugin. Best-effort
          // detach reverses that; failures during cleanup are swallowed
          // because the original attach error is what the caller cares
          // about.
          try {
            await plugin._runDetach(session.context);
          } catch (_) {}
          // Roll back the partial registration so the registry does not
          // hold orphan wrappers for a plugin that never attached. State
          // queries (session.isPluginEnabled, runtime.attachedPluginIds)
          // must report the plugin as NOT enabled after this failure.
          final serviceIds = registry.listAllServiceIds(plugin.pluginId);
          for (final serviceId in serviceIds) {
            registry.unregister(
              pluginId: plugin.pluginId,
              serviceId: serviceId,
            );
          }
          continue;
        }
        // Both register and attach succeeded: only NOW record the plugin
        // as enabled in this session.
        session.markPluginEnabled(plugin.pluginId);
      }
    }
    if (errors.isNotEmpty) {
      throw PluginLifecycleException('updateSessionSettings', errors);
    }
  }

  /// Snapshot of currently-attached stateful services per plugin in
  /// [pluginIds], keyed by `(pluginId, serviceId)`. Used as the pre-state
  /// for the override-flip diff in [_reconcileServiceLifecycleDiff].
  /// Factories are skipped (cannot host stateful services); disabled
  /// wrappers are filtered by [ServiceRegistry.getPluginServicesWithIds].
  Map<(PluginId, ServiceId), StatefulPluginService>
  _snapshotAttachedStatefulServices({
    required ServiceRegistry registry,
    required Iterable<PluginId> pluginIds,
  }) {
    final snapshot = <(PluginId, ServiceId), StatefulPluginService>{};
    for (final pluginId in pluginIds) {
      for (final (serviceId, instance) in registry.getPluginServicesWithIds(
        pluginId,
        skipFactories: true,
      )) {
        if (instance is StatefulPluginService && instance.hasContext) {
          snapshot[(pluginId, serviceId)] = instance;
        }
      }
    }
    return snapshot;
  }

  /// Diff [preAttached] (captured before the override flip) against the
  /// current enabled set and run lifecycle on transitions: enabled to
  /// disabled gets `detach()` + unbind; disabled to enabled gets bind +
  /// `attach()`. Returns errors as `(pluginId, error, stackTrace)` tuples
  /// for aggregation. Fatal VM errors are rethrown.
  Future<List<(PluginId, Object, StackTrace)>> _reconcileServiceLifecycleDiff({
    required ServiceRegistry registry,
    required Iterable<PluginId> pluginIds,
    required Map<(PluginId, ServiceId), StatefulPluginService> preAttached,
    required PluginContext context,
  }) async {
    final errors = <(PluginId, Object, StackTrace)>[];

    final postEnabled = <(PluginId, ServiceId), StatefulPluginService>{};
    for (final pluginId in pluginIds) {
      for (final (serviceId, instance) in registry.getPluginServicesWithIds(
        pluginId,
        skipFactories: true,
      )) {
        if (instance is StatefulPluginService) {
          postEnabled[(pluginId, serviceId)] = instance;
        }
      }
    }

    // Detach services that flipped enabled -> disabled.
    for (final entry in preAttached.entries) {
      if (postEnabled.containsKey(entry.key)) continue;
      final (pluginId, serviceId) = entry.key;
      final service = entry.value;
      try {
        await service.detach();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _runtimeLog.severe(
          'Service "$serviceId" of plugin "$pluginId" detach() threw '
          'while reconciling disabled override',
          e,
          st,
        );
        errors.add((pluginId, e, st));
      }
      final unbindFailures = await service._unbindContext();
      for (final (step, e, st) in unbindFailures) {
        _runtimeLog.severe(
          'Service "$serviceId" of plugin "$pluginId" $step threw during '
          'override-driven unbind',
          e,
          st,
        );
        errors.add((pluginId, e, st));
      }
    }

    // Attach services that flipped disabled -> enabled. Skip those already
    // attached (e.g. via the plugin enable path inside
    // _reconcilePluginsOnSettingsUpdate or _updateGlobalSettingsInternal's
    // own plugin-transition loop).
    for (final entry in postEnabled.entries) {
      if (preAttached.containsKey(entry.key)) continue;
      final (pluginId, serviceId) = entry.key;
      final service = entry.value;
      if (service.hasContext) continue;
      service._bindContext(context);
      try {
        service.attach();
      } catch (e, st) {
        if (_isFatalError(e)) rethrow;
        _runtimeLog.severe(
          'Service "$serviceId" of plugin "$pluginId" attach() threw '
          'while reconciling enabled override',
          e,
          st,
        );
        errors.add((pluginId, e, st));
        // Best-effort unwind: bind happened above but attach() never
        // completed. _unbindContext cancels any subscriptions opened
        // before the throw and clears _context.
        final unbindFailures = await service._unbindContext();
        for (final (step, ue, ust) in unbindFailures) {
          _runtimeLog.severe(
            'Service "$serviceId" of plugin "$pluginId" $step threw during '
            'attach-failure unwind',
            ue,
            ust,
          );
          errors.add((pluginId, ue, ust));
        }
      }
    }

    return errors;
  }

  /// Determine if a plugin would be enabled for a given [settings] snapshot.
  ///
  /// When [settings] is null, the runtime's current snapshot ([this.settings])
  /// is used.
  ///
  /// Applies the same precedence as [_determineEnabledPluginIds]: locked
  /// plugins are always enabled, explicit config wins over defaults, and
  /// experimental plugins are disabled by default. Dependency validation is
  /// not applied here: this returns the base enablement only.

  /// Reconciles the runtime to [newSettings] in serialized order: global
  /// scope first, then each active session sequentially. Transactional:
  /// on any failure, every touched unit is reverted via a re-reconcile
  /// pass back to the prior snapshot, the stored snapshot stays at the
  /// previous value, and the original exception is rethrown. Secondary
  /// failures during the revert pass log severe but never suppress the
  /// primary; fatal VM errors during revert supersede it.
  Future<void> _updateSettingsImpl(RuntimeSettings newSettings) async {
    if (!_initialized || _disposed) {
      throw StateError(
        'PluginRuntime.updateSettings() called ${_disposed ? 'on a disposed runtime' : 'before init()'}. '
        'Call init() first.',
      );
    }
    _enterReconcile('updateSettings');
    try {
      final oldSettings = _settings;
      // Snapshot per-session settings BEFORE any mutation so a failed
      // reconcile can roll each session back to ITS OWN pre-update state.
      // We can't trust live `_sessionSettings` during rollback because the
      // success-path code below mutates it as each per-session pass commits.
      final preUpdateSessionSettings =
          Map<PluginSession<S>, RuntimeSettings>.from(_sessionSettings);
      // Normalize at the boundary: defensive copy of caller maps + filter
      // entries that reference unknown plugin/service ids under the active
      // [UnknownReferencePolicy]. `globalRegistry` is already populated, so
      // we can also run the service-id pass here.
      final effectiveSettings = _normalizeSettings(
        entryPoint: 'updateSettings',
        raw: newSettings,
        scopePlugins: globalPlugins,
        registryForServiceIdCheck: globalRegistry,
      );
      // Tracks units mid-reconcile so the catch can roll them back too.
      // A unit that throws partway still left fully-transitioned plugins
      // on the new state (per-plugin rollback only unwinds the thrower);
      // skipping the in-flight unit would leave it half-applied while
      // every completed sibling reverts cleanly.
      final reconciledSessions = <PluginSession<S>>[];
      bool globalStarted = false;
      PluginSession<S>? inFlightSession;

      try {
        globalStarted = true;
        await _updateGlobalSettingsInternal(
          oldSettings: oldSettings,
          newSettings: effectiveSettings,
        );

        for (final session in _sessions) {
          inFlightSession = session;
          await _updateSessionSettingsInternal(
            session,
            newSettings: effectiveSettings,
          );
          _sessionSettings[session] = effectiveSettings;
          reconciledSessions.add(session);
          inFlightSession = null;
        }
        if (!_initialized || _disposed) {
          throw StateError(
            'PluginRuntime.updateSettings() called on a disposed runtime. '
            'Call init() first.',
          );
        }
        _settingsValue = effectiveSettings;
      } catch (e) {
        // Revert order: GLOBAL first, then in-flight session, then
        // completed sessions in reverse. Session enablement depends on
        // `_enabledGlobalPluginIds` for dependency cascade, so reverting
        // global first restores the cascade input each session's
        // rollback reconcile reads. Global revert runs on either
        // `globalStarted` outcome because a partial reconcile still
        // left mutations.
        if (globalStarted) {
          try {
            await _updateGlobalSettingsInternal(
              oldSettings: newSettings,
              newSettings: oldSettings,
            );
          } catch (rollbackError, rollbackSt) {
            if (_isFatalError(rollbackError)) rethrow;
            _runtimeLog.severe(
              'updateSettings rollback failed for global; the original '
              'reconcile exception is rethrown and this secondary error '
              'is surfaced here only',
              rollbackError,
              rollbackSt,
            );
          }
        }
        if (inFlightSession != null) {
          try {
            // Restore from the pre-update snapshot, NOT the live
            // `_sessionSettings` map (which the success path already
            // partially mutated as earlier sessions committed).
            await _updateSessionSettingsInternal(
              inFlightSession,
              newSettings:
                  preUpdateSessionSettings[inFlightSession] ?? oldSettings,
            );
            _sessionSettings[inFlightSession] =
                preUpdateSessionSettings[inFlightSession] ?? oldSettings;
          } catch (rollbackError, rollbackSt) {
            if (_isFatalError(rollbackError)) rethrow;
            _runtimeLog.severe(
              'updateSettings rollback failed for in-flight session; the '
              'original reconcile exception is rethrown and this '
              'secondary error is surfaced here only',
              rollbackError,
              rollbackSt,
            );
          }
        }
        for (final session in reconciledSessions.reversed) {
          try {
            await _updateSessionSettingsInternal(
              session,
              newSettings: preUpdateSessionSettings[session] ?? oldSettings,
            );
            _sessionSettings[session] =
                preUpdateSessionSettings[session] ?? oldSettings;
          } catch (rollbackError, rollbackSt) {
            if (_isFatalError(rollbackError)) rethrow;
            _runtimeLog.severe(
              'updateSettings rollback failed for session; the original '
              'reconcile exception is rethrown and this secondary error '
              'is surfaced here only',
              rollbackError,
              rollbackSt,
            );
          }
        }
        rethrow;
      }
    } finally {
      _reconciling = false;
    }
  }

  /// Mark a reconciliation pass as in flight, or throw if one already is.
  /// Paired with `_reconciling = false` in a `finally` so failed reconciles
  /// do not leave the runtime permanently locked.

  /// Update global plugin settings with reconciliation.
  ///
  /// Reconciles plugin enablement (disable/enable) and notifies remaining
  /// enabled global plugins via [Plugin.onPluginSettingsChanged].
  Future<void> _updateGlobalSettingsImpl({
    required RuntimeSettings oldSettings,
    required RuntimeSettings newSettings,
  }) async {
    _enterReconcile('updateGlobalSettings');
    try {
      await _updateGlobalSettingsInternal(
        oldSettings: oldSettings,
        newSettings: newSettings,
      );
    } finally {
      _reconciling = false;
    }
  }

  /// Body of [updateGlobalSettings] without the re-entry guard. Used by
  /// [updateSettings] which already holds the guard for the whole pass.

  /// Body of [updateGlobalSettings] without the re-entry guard. Used by
  /// [updateSettings] which already holds the guard for the whole pass.
  Future<void> _updateGlobalSettingsInternal({
    required RuntimeSettings oldSettings,
    required RuntimeSettings newSettings,
  }) async {
    final oldContext = globalContext.copyWith();
    // See the matching assert in `_updateSessionSettingsInternal` for the
    // rationale; this is intentionally over-constrained for the same reason.
    assert(
      oldContext.runtimeType == globalContext.runtimeType,
      'Custom global context subclass ${globalContext.runtimeType} did not '
      'override copyWith(); onPluginSettingsChanged will receive a base-type '
      'oldContext and any covariant subtype override on the plugin will throw '
      'TypeError. See concepts/custom-context for the required override shape.',
    );
    _validateServiceSettingPluginIds(
      entryPoint: 'updateGlobalSettings',
      services: newSettings.services,
    );
    _validatePluginConfigPluginIds(
      entryPoint: 'updateGlobalSettings',
      plugins: newSettings.plugins,
    );

    final overrides = <LocalPluginOverride>[];
    final pendingWildcards = <ServiceId, ServiceSettings>{};
    _partitionServiceSettings(
      services: newSettings.services,
      overrides: overrides,
      pendingWildcards: pendingWildcards,
      plugins: globalPlugins,
    );
    final enabledPluginIds = _determineEnabledPluginIds(
      newSettings,
      pluginSubset: globalPlugins,
    );

    final errors = <(PluginId, Object, StackTrace)>[];
    for (final plugin in globalPlugins) {
      final wasEnabled = _enabledGlobalPluginIds.contains(plugin.pluginId);
      final isEnabled = enabledPluginIds.contains(plugin.pluginId);

      // Disable: detach and unregister
      if (wasEnabled && !isEnabled) {
        try {
          await plugin._runDetach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to detach global plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
        }
        final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
        for (final id in serviceIds) {
          globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
        }
        _enabledGlobalPluginIds.remove(plugin.pluginId);
        _runtimeLog.info(
          'Global settings update: disabled plugin "${plugin.pluginId}"',
        );
      }
      // Enable: register and attach
      else if (!wasEnabled && isEnabled) {
        try {
          plugin.register(globalRegistry.scopedFor(plugin.pluginId));
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to register global plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          continue;
        }
        try {
          plugin._runAttach(globalContext);
        } catch (e, st) {
          if (_isFatalError(e)) rethrow;
          _runtimeLog.severe(
            'Failed to attach global plugin "${plugin.pluginId}" during settings update',
            e,
            st,
          );
          errors.add((plugin.pluginId, e, st));
          // Cleanup pass: see the matching comment in the session enable
          // path. `_runAttach` may have left service contexts bound and
          // subscriptions live before throwing; best-effort detach
          // reverses that. Failures during cleanup are swallowed; the
          // original attach error already surfaces.
          try {
            await plugin._runDetach(globalContext);
          } catch (_) {}
          // Roll back the partial registration so attachedGlobalPluginIds
          // does not advertise a plugin whose attach failed and so the
          // global registry is not left with orphan wrappers.
          final serviceIds = globalRegistry.listAllServiceIds(plugin.pluginId);
          for (final id in serviceIds) {
            globalRegistry.unregister(pluginId: plugin.pluginId, serviceId: id);
          }
          continue;
        }
        // Both register and attach succeeded: only NOW record the plugin
        // as attached at the global scope.
        _enabledGlobalPluginIds.add(plugin.pluginId);
        _runtimeLog.info(
          'Global settings update: enabled plugin "${plugin.pluginId}"',
        );
      }
    }

    // Validate service pin service ids now that newly-enabled global
    // plugins have registered and disabled ones have been unregistered.
    _validateServicePinServiceIds(
      entryPoint: 'updateGlobalSettings',
      registry: globalRegistry,
      services: newSettings.services,
      plugins: globalPlugins,
    );

    // Snapshot attached stateful services BEFORE the override flip
    // below (either _resolveAndApplyWildcards or the unconditional
    // updateSettings call may apply it). The post-flip diff handles
    // service-level enable/disable transitions for plugins that stay
    // enabled across the update.
    final preAttached = _snapshotAttachedStatefulServices(
      registry: globalRegistry,
      pluginIds: _enabledGlobalPluginIds,
    );

    // Always call updateSettings even when both lists are empty so
    // wrappers whose priority overrides were just removed get restamped
    // back to their basePriority.
    _resolveAndApplyWildcards(
      registry: globalRegistry,
      pendingWildcards: pendingWildcards,
      overrides: overrides,
    );
    if (pendingWildcards.isEmpty) {
      globalRegistry.updateSettings(overrides: overrides);
    }

    final serviceErrors = await _reconcileServiceLifecycleDiff(
      registry: globalRegistry,
      pluginIds: _enabledGlobalPluginIds,
      preAttached: preAttached,
      context: globalContext,
    );
    errors.addAll(serviceErrors);

    // Notify remaining enabled global plugins of settings changes
    for (final pluginId in _enabledGlobalPluginIds) {
      final plugin = _plugins.firstWhereOrNull((p) => p.pluginId == pluginId);
      if (plugin != null) {
        await plugin.onPluginSettingsChanged(oldContext, globalContext);
      }
    }
    if (errors.isNotEmpty) {
      _runtimeLog.warning(
        'Global settings updated with ${errors.length} plugin failure(s)',
      );
      throw PluginLifecycleException('updateGlobalSettings', errors);
    }
    _runtimeLog.info('Global settings updated');
  }

  /// Dispose runtime: detach all global plugins, dispose sessions.
}
