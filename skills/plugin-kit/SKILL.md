---
name: plugin-kit
description: Use when writing or modifying Dart code that imports `package:plugin_kit/plugin_kit.dart` - building plugins, registering services, wiring events, configuring runtime settings, or designing how a feature should split across the Plugin/Service boundary.
---

# plugin_kit

A Dart plugin runtime for building modular, composable systems. Plugins register services into a priority-ordered registry and communicate through a typed event bus. Behavior is replaced and tuned through the registry; communication happens through the bus.

Three primitives:
- Service registry: priority, override, disable, hot-swap, keyed by `ServiceId`. Higher priority wins; settings can override or disable per-slot.
- Event bus: envelope cascade with mutation and stop, plus typed request/response. Handlers can mutate the payload, halt the cascade with a value, or chain through priorities.
- Plugin lifecycle: `register` then `attach` then `detach`. Scope is `GlobalPlugin` (one instance per runtime) or `SessionPlugin` (one instance shared across sessions, with per-session service instances).

## Pick a service base class

Plugin classes register services and contain no behavior. `Plugin.attach` subscriptions are wiring only (debug taps, internal bridges between services this plugin owns). Behavior another plugin should override, settings-tune, or disable belongs in a service. Once it's a service, pick the base class:

```
needs settings injection from RuntimeSettings.services?
  no -> plain Dart class. registerFactory / registerSingleton / registerLazySingleton.
  yes -> needs lifecycle, events, or session-bound state?
    no -> PluginService. Override onSettingsInjected() to react.
    yes -> StatefulPluginService. registerSingleton / registerLazySingleton ONLY.
           Auto-tracked helpers: on, onRequest, onRequestSync, bind, emit (read this.context).
```

For event-driven slots:
```
multiple registrants should all run (pipeline, validators, layered enrichment)?
  yes -> each registrant subscribes directly at staggered priority. Cascade runs them all.
  no, exactly-one-wins -> single dispatcher subscription resolves the winning slot per event and delegates.
                          See patterns.md for the dispatcher form.
```

## API surface

Full surface lives in api-cheatsheet.md. Quick pointers:

- Typed handles (`PluginId`, `ServiceId`, `Namespace`, `PluginNamespaced`, `Pin`): section 1.
- Plugin / StatefulPluginService helpers (`on`, `onRequest`, `onRequestSync`, `bind`, `emit`) and resolution methods (`resolve`, `maybeResolve`, `resolveAfter`): sections 2, 4.
- `EventEnvelope`, request/response: section 5.
- `EventBinding<E>` extension type: section 5. Wraps the `StreamSubscription` returned from `on`/`bind` with typed `cancel()` plus the listener-lifecycle utilities consumed by the Flutter integration.
- `onPluginSettingsChanged`: section 2.

`context.bus` is the raw `EventBus`; reach for it only when a subscription's lifetime should not match the plugin/service.

### From Flutter widgets

Flutter integration lives in `package:flutter_plugin_kit/flutter_plugin_kit.dart`, NOT in plugin_kit itself. Use it instead of holding `_runtime`/`_session` fields and manual `StreamSubscription` plumbing on a `State`:

- `PluginRuntimeScope` owns or carries a `PluginRuntime`. Two constructors: bare (give it a `plugins:` list, scope calls `init`/`dispose`) or `PluginRuntimeScope.value(runtime: ...)` for an externally-owned runtime.
- `PluginSessionScope` owns or carries a `PluginSession`. Resolution order: explicit `session:`, then explicit `runtime:`, then ambient `PluginRuntimeScope`. Pass at most one of `session`/`runtime` (asserted in debug).
- `PluginSessionListener<E>` widget rebuilds on matching events from the ambient session.
- `PluginSessionStateListener` mixin replaces inline `session.on<E>(...)` plumbing on a `State`. It tracks bindings, cancels them on dispose, and re-attaches across session swap. Pair with `BuildContext.watchEvent<E>()` / `readEvent<E>()` to read the latest event during build without manual subscription.

Plugin and service code stays the same. The mixins are widget-side adapters; they consume the same `EventBus` and `PluginSession` the Dart-only API exposes.

## Conventions

1. User hooks never call super. `attach`, `detach`, and `onSettingsInjected` are pure user hooks; the framework orchestrates around them. `injectSettings` itself is `@nonVirtual` and runs bookkeeping; override `onSettingsInjected()` to react.

2. `registerSingleton<T>(id, Factory<T> create)` runs the factory once at registration. `register()` runs per session for `SessionPlugin`, so an inline `() => T()` gives one instance per session; `() => _shared` shares. `registerLazySingleton` defers to first resolve; `registerFactory` re-runs every resolve. Namespacing is composition into the `ServiceId` string, not a separate registry.

3. Plugin helpers require explicit `context` as first arg. Plugin instances are shared across sessions; no `this.context` exists because storing one would lie when a second session attaches. StatefulPluginService instances scope to whichever plugin owns them: a `SessionPlugin`'s services construct fresh per session (because `register()` runs per session); a `GlobalPlugin`'s services construct once per runtime. Either way each instance binds to one context for its lifetime, so `this.context` is safe and helpers read it implicitly.

4. Resolve at point of use for hot-swappable slots. Caching `final svc = context.resolve<X>(...)` at attach time freezes you on the winner that existed at attach time. A higher-priority plugin enabled later won't show up. Holding fields for components you registered yourself (your own state) is state ownership, not the same thing.

5. Lifecycle is register-all then attach-all. During session creation: every enabled plugin runs `register()` (undefined order); wildcard overrides resolve; every enabled plugin runs `attach(context)`. Don't `resolve` from inside `register()` (other plugins may not have registered). Resolve in `attach`, in event handlers, or via `registerLazySingleton` with closure-captured registry.

6. Settings reconciliation: newly-enabled plugins run `register()` then `attach`; staying-enabled plugins get `onPluginSettingsChanged(oldContext, newContext)`; newly-disabled plugins detach and unregister. Plugin instances persist; service instances are recreated. See api-cheatsheet.md for full phase order.

7. Priority: higher wins / runs first in both subsystems. Default is `Priority.normal`. Named stops `lowest`/`low`/`normal`/`elevated`/`high`/`system`; `Priority.above(other, by: N)` / `Priority.below(other)` for relative.

8. Events: mutable T fields on the event class when interception is the contract (pre-commit drafts, stream-wrapping). Final T fields when the event is a fact or notification. Mutability is a contract signal to handlers, not a default.

9. Default-context generics are inferred. `extends SessionPlugin` infers `<SessionPluginContext>`; `extends GlobalPlugin` infers `<GlobalPluginContext>`; `PluginRuntime` and `PluginRuntime` infer `<GlobalPluginContext, SessionPluginContext>`; `PluginSession` infers `<SessionPluginContext>`. Specify generics only when using a custom context subclass.

   `StatefulPluginService<PKC extends PluginContext>` has a wider bound because it can host both global and session services. Bare `extends StatefulPluginService` infers `<PluginContext>`, which limits `this.context` to the base type. Two ergonomic typedef aliases ship with the library: `extends SessionStatefulPluginService` (alias for `StatefulPluginService<SessionPluginContext>`) and `extends GlobalStatefulPluginService` (alias for `StatefulPluginService<GlobalPluginContext>`). The aliases are pure syntactic sugar; the explicit `extends StatefulPluginService<S>` form still works and is required when `S` is a custom context subclass.

10. `enabledPlugins` is settings-intent (what `RuntimeSettings` says is on); `attachedPlugins` is runtime-effective (what the runtime actually attached after dependency cascade). Use `enabledPlugins` for settings UI; `attachedPlugins` for "is it actually running." Per-scope underliers and full semantics in api-cheatsheet.md.

11. `PluginId` values starting with `__pk_` are reserved for internal sentinels (`PluginId.wildcard.value == '__pk_wildcard__'`, `PluginId.winnerScoped.value == '__pk_winner__'`). `PluginRuntime.addPlugin` rejects any user-supplied id with that prefix. Pick any other naming; plugin ids conventionally read as lowercase_snake_case (`chat`, `model_router`).

12. Request/response failure is a typed exception. `context.bus.request<R, S>(req)` and `requestSync<R, S>(req)` throw `RequestUnavailableException` when no handler is registered or every handler conceded with null on a non-nullable `S`. `maybeRequest` and `maybeRequestSync` convert ONLY that exception to null; handler-thrown exceptions propagate. `null` means "request unavailable," not "handler crashed." Catch `RequestUnavailableException` when you need to distinguish.

## Reading guide

Task -> file.

- Replacing or overriding behavior across plugins: patterns.md #1.
- Walking the priority chain (skip-self, fallback): patterns.md #2, #6.
- Per-session state, lifecycle, settings reconciliation: api-cheatsheet.md sections 2, 7, 8.
- Const vs runtime ServiceId composition: patterns.md #4, api-cheatsheet.md section 1.
- Pre-commit interception (mutate or veto an action): patterns.md #5.
- Capabilities, FeatureFlag: api-cheatsheet.md sections 2, 3.
- Testing without a runtime: testing.md.
- Suspecting code is broken: anti-patterns.md (red-flag index at top).

## Source pointers

- `packages/plugin_kit/lib/src/`
- `example/villain_lair/bin/01_hello_lair.dart` for the minimal end-to-end shape; `02..15_*.dart` add capabilities, sessions, dependencies, settings reconciliation, identifier scoping.
- `example/code_editor/`, `example/model_embassy/`, `example/state_garden/`, `example/plugin_kit_dialog_demo/`
- `packages/plugin_kit_dialog/` (optional UI configurability)
