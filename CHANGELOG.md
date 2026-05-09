## Unreleased

- `flutter_plugin_kit` (0.1.0) — Flutter ergonomics on top of `plugin_kit`. Ships:
  - `PluginRuntimeScope` and `PluginSessionScope` `InheritedWidget`s that carry a `PluginRuntimeManager` / `PluginSession` through the tree. The runtime scope distinguishes scope-owned (`PluginRuntimeScope(plugins: ...)`) from caller-owned (`PluginRuntimeScope.value(runtime: ...)`) via two named constructors with `Provider.value`-style semantics. The session scope likewise picks scope-owned vs caller-owned by which argument is supplied — `PluginSessionScope(session: ...)` for an externally-owned session, `PluginSessionScope(runtime: ...)` (or no argument, falling through to the ambient `PluginRuntimeScope`) for the auto-create variant.
  - `PluginSessionStateListener<W>`, a mixin on `State<W>`. `listen<E>(handler)` and `rebuildOn<E>([when])` register subscriptions that auto-cancel on dispose and re-attach across session swaps. Both are callable from `initState` (and any later lifecycle callback). Reactive to `PluginSessionScope` changes, `widget.session` swaps, and ambient `PluginRuntimeScope` swaps in auto-create mode.
  - `PluginEventNotifier<E>`, a `ChangeNotifier` / `ValueListenable<E?>` that exposes the latest event of a type as `.value`. Drops into `ChangeNotifierProvider`, `ValueListenableProvider`, `ValueListenableBuilder`, and any other foundation-listenable consumer without a custom adapter.
  - `BuildContext.watchEvent<E>()` / `readEvent<E>()` — ambient-session extensions for the calling element to subscribe to (or read) the latest `E` without a state holder.
  - Pure-Dart `PluginSessionListener` mixin and shared `EventBinding` descriptor in `plugin_kit` itself, for hosts (cubits, controllers) that want the same declarative subscription shape without Flutter.

- `EventBus` post-dispose guards now apply uniformly to every mutating method (`bind`, `on`, `emit`, `request`, `onRequest`, `requestSync`, `emitSync`, plus all `*Sync` variants via their delegates). Calling any of these on a disposed bus throws `StateError` instead of silently no-opping.

- `EventBus.emit` / `emitSync` / `request` / `requestSync` now always iterate a snapshot of the merged handler list. Previously, when one of the two handler buckets (general vs identifier-scoped) was empty, dispatch iterated the live backing list — a handler that cancelled itself or another subscription mid-cascade could trigger `ConcurrentModificationError` or skip a still-registered handler. The dispatch contract now matches the docs unconditionally.

- Settings-driven priority overrides apply live. Previously, changing `ServiceSettings.priority` for an already-registered plugin updated the override list but left the existing wrapper's stored priority at its registration-time value, so the live winner did not change until the plugin was re-registered (i.e. on session re-create or detach/attach). `ServiceRegistry.updateSettings` now restamps each wrapper's effective priority from the new override list and re-sorts in place, so toggle-priority and remove-priority both take effect on the next resolve. `RegistrationWrapper.basePriority` exposes the registration-time value separately for tests and tooling.

- Removed `UiVisualsCapability` from `plugin_kit_dialog`. The capability was orphaned (not exported, not consumed by the runtime) once visuals consolidated onto `PluginKitVisualsPlugin`. Hosts that still reference it should attach a `PluginKitVisualsPlugin` instead and key visuals by `PluginId` / `Namespace` / `ServiceId` from there.

### Tracked follow-ups (not in this release)

Roadmap items live in `docs/superpowers/plans/`. See `2026-05-09-v0.2-followups.md` (constructor split, vocabulary collapse, Flutter doc consolidation) and `2026-05-09-doc-drift-mitigation.md` (doc-drift automation).

## 1.0.0

First public release. Highlights:

- Plugin runtime with global and session scopes. Plugins extend `GlobalPlugin<G>` (one instance per runtime) or `SessionPlugin<S>` (one instance shared across sessions, with per-session service instances). Lifecycle is `register` then `attach` then `detach`. `attach` and `detach` are pure user hooks; the framework drives orchestration through library-private `_runAttach` / `_runDetach`.

- Service registry with priority, override, disable, and hot-swap, keyed by typed `ServiceId` handles. Higher priority wins resolution; `RuntimeSettings.services` can override or disable per-slot. Wildcard overrides target whichever plugin currently wins resolution for a given `ServiceId`.

- Typed event bus with envelope cascade, mutation, and stop, plus typed request/response. Handlers run in ascending priority order. Cascade can be halted with `EventEnvelope.stop(value)`. `request` throws on availability failure; `maybeRequest` returns null for "no handler" or "all handlers conceded" but propagates handler exceptions. `RequestUnavailableException` is the typed availability marker.

- Settings reconciliation. `RuntimeSettings` is JSON-serializable. `PluginRuntimeManager.updateSettings` runs serialized reconciliation across global scope first, then each active session in order; settings persist only after all reconciles succeed.

- `enabledPlugins` (settings-intent) and `attachedPlugins` (runtime-effective). The former reports what `RuntimeSettings` says is on; the latter reports the dependency-validated set the runtime actually attached. A plugin enabled in settings but cascade-disabled because its dependency is off appears in `enabledPlugins` but not `attachedPlugins`.

- Sentinel reservation. `PluginId` values starting with `__pk_` are reserved for internal sentinels (`PluginId.wildcard` = `__pk_wildcard__`, `PluginId.winnerScoped` = `__pk_winner__`). `PluginRuntime.addPlugin` rejects any user-supplied id starting with `__pk_`. The wire format for `ScopedServiceKey.wildcard` remains `*:` for JSON round-trip.

- `plugin_kit_dialog` companion package: drop-in Flutter UI that reflects the runtime's state live. Toggle plugins, edit settings, inspect the registry. Lives in its own package so non-Flutter consumers of `plugin_kit` never pull in Flutter.

- Examples: `state_garden` (the same chat protocol bridged to seven Flutter state-management libraries side by side), `code_editor` (Flutter capstone with multiple plugin tiers), `model_embassy` and `villain_lair` (pure-Dart numbered-bin tutorials), `plugin_kit_dialog_demo` (the dialog package).

SDK floor: Dart `>=3.10.0`. Required for extension type dot-shorthand (`[.experimental]`).
