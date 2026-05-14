# plugin_kit: API cheatsheet

Dense reference. Source pointers at the end.

## Index

1. Typed handles
2. Plugin lifecycle (FeatureFlag, scope, helpers)
3. Service registry (Capabilities)
4. PluginService base classes
5. Event bus
6. RuntimeSettings
7. Sessions
8. Runtime (enabled vs attached)
9. Source pointers

## Typed handles (`typed_handles.dart`)

Zero-cost extension types over `String`. At runtime they are the underlying String.

```dart
/// Full typed-handles index: PluginId, Namespace, ServiceId, and Pin.
void demonstrateTypedHandlesIndex() {
  const PluginId chatId = PluginId('chat');
  const Namespace agent = Namespace('agent');
  const ServiceId modelId = ServiceId('agent.model');

  // Sentinels.
  const wildcard = PluginId.wildcard;
  const winnerScoped = PluginId.winnerScoped;

  // Namespace members.
  final agentValue = agent.value;
  final systemPromptNs = agent.child('system_prompt');
  final modelIdFromNs = agent.service('model');
  final modelIdShorthand = agent('model');

  // ServiceId members.
  final modelValue = modelId.value;
  final modelNs = modelId.namespace;
  final modelLeaf = modelId.id;
  final modelTopNs = modelId.topNamespace;
  const modelNamespaced = ServiceId.namespaced(agent, 'model');

  // Pin construction via typed chain.
  final pin1 = chatId.service(modelId);
  final pin2 = PluginId.wildcard.service(modelId);
  final pin3 = const PluginId('chat').namespace('agent').service('model');
  final pin4 = const PluginId('chat').namespace('agent')('model');

  // Pin construction directly.
  final pin5 = Pin('chat', ['agent', 'model']);
  final pin6 = Pin('chat', ['greeter']);
  final pin7 = Pin.wildcard(['agent', 'tools']);

  // Pin inspection.
  final pin = Pin('chat', ['agent', 'model']);
  final pluginId = pin.pluginId;
  final serviceId = pin.serviceId;
  final isWildcard = pin.isWildcard;
  final wire = pin.wire;

  // Const-friendly wire parse.
  const constPin1 = Pin.fromWire('chat:agent.model');
  const constPin2 = Pin.fromWire('*:agent.tools');

  print(
    '$chatId $agent $modelId $wildcard $winnerScoped '
    '$agentValue $systemPromptNs $modelIdFromNs $modelIdShorthand '
    '$modelValue $modelNs $modelLeaf $modelTopNs $modelNamespaced '
    '$pin1 $pin2 $pin3 $pin4 $pin5 $pin6 $pin7 '
    '$pluginId $serviceId $isWildcard $wire '
    '$constPin1 $constPin2',
  );
}
```

`PluginId`, `Namespace`, `ServiceId`, and `Pin` all declare `implements String`, so a typed identifier flows directly into any `String`-typed parameter, JSON key, log interpolation, or `Map<String, T>` lookup with no `.value` / `.wire` / cast at the call site. The reverse direction (raw `String` into a typed slot) still fails to compile, so registry boundaries keep their type discipline. `PluginId.service` accepts a bare dotted path: `pluginId.service('a.b.c')` produces the same `Pin` as `pluginId.service(const ServiceId('a.b.c'))`. `Namespace.has(ServiceId)` is the typed namespace-containment predicate (matches direct children and nested descendants).

`Namespace.call`, `.service`, `.child` and `PluginId.service`, `PluginId.namespace`, `PluginNamespaced.service`, `.child`, `.call` are runtime helpers. `Pin(plugin, segments)` and `Pin.wildcard(segments)` join segments with `'.'` so both are non-const. `Pin.fromWire(String)` is the only const-friendly Pin constructor. Use it for fully-literal const settings, or use `final` for typical runtime construction.

## Plugin lifecycle (`plugin/core.dart`, `plugin/plugin.dart`, `plugin/runtime.dart`)

```dart
class MyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_plugin');

  @override
  Set<PluginId> get dependencies => const {PluginId('other_plugin')};

  @override
  List<FeatureFlag> get featureFlags => const [];  // .experimental, .locked

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<MyService>(const ServiceId('my'), () => MyService());
  }

  @override
  void attach(SessionPluginContext context) {
    on<MyEvent>(context, (e) => /* ... */);
  }

  @override
  Future<void> detach(SessionPluginContext context) async {}

  @override
  Future<void> onPluginSettingsChanged(
    SessionPluginContext oldContext,
    SessionPluginContext newContext,
  ) async {}
}
```

Phase order:
1. `addPlugin(...)`: runtime stores instance. One per `pluginId` ever.
2. `init()` / `createSession()`: register-all on every enabled plugin (undefined order); resolve wildcard overrides; attach-all on every enabled plugin. Framework runs `_runAttach` / `_runDetach` orchestration around user hooks.
3. Settings reconciliation: newly-disabled plugins detach + unregister; newly-enabled plugins register + attach; staying-enabled plugins get `onPluginSettingsChanged(oldContext, newContext)`. Plugin instances persist; service instances recreate (`register()` re-runs).
4. `dispose()`: every enabled plugin's `detach(context)` runs.

Failure isolation during attach/detach:
- Each step (service `attach`/`detach`, plugin `attach`/`detach`, subscription/binding cancel) runs in its own try/catch. A throwing step is logged and recorded; remaining steps still run so peers get torn down cleanly.
- One step failed: that original exception is rethrown unchanged so callers can pattern-match on its concrete type.
- Two or more steps failed: a `PluginStepAggregateException` wraps them; iterate `stepFailures` for `(stepName, error, stackTrace)` tuples. Step names are stable strings (`'attach'`, `'detach'`, `'<serviceId>.attach'`, `'subscription.cancel'`, etc.) and survive minification.
- Re-entry during teardown is rejected. Calling `on(context, ...)` or `bind(context, ...)` from inside a `sub.cancel()` callback during detach surfaces as a `'subscription.leak'` / `'binding.leak'` step failure; the new entries are dropped without being cancelled rather than silently leaking.
- The runtime catches whichever exception bubbles up and folds it into one entry of `PluginLifecycleException.failures`.

FeatureFlag (`Plugin.featureFlags`):
- `.locked`: always enabled; cannot be disabled via `RuntimeSettings`.
- `.experimental`: disabled by default; requires opt-in via an explicit `RuntimeSettings.plugins[id]` entry with `enabled: true`.
- Custom flags: `const FeatureFlag('your_string')`. Zero-cost extension type over String.

Enablement precedence per plugin (highest to lowest): `.locked` (forced on) → explicit `RuntimeSettings.plugins[id].enabled` → experimental heuristic (non-experimental defaults on, `.experimental` defaults off). Build a `RuntimeSettings` listing the subset you want enabled to override the defaults.

Scope:
- `GlobalPlugin<G extends GlobalPluginContext>`: one instance per runtime; lifetime equals runtime.
- `SessionPlugin<S extends SessionPluginContext>`: one instance per `pluginId` shared across all sessions; lifetime equals runtime. `attach(S context)` runs once per session attach. Service instances inside are per-session because `register()` runs per-session and inline construction evaluates fresh.

User hooks never call super. `attach`, `detach`, and `onSettingsInjected` are framework-orchestrated; `injectSettings` itself is `@nonVirtual`. Override `onSettingsInjected()` to react.

Default-context generics are inferred. `extends SessionPlugin` infers `<SessionPluginContext>`; `extends GlobalPlugin` infers `<GlobalPluginContext>`; `PluginRuntime` and `PluginRuntime` default to `<GlobalPluginContext, SessionPluginContext>`; `PluginSession` defaults to `<SessionPluginContext>`. Spell the type parameters out only when using a custom context subclass.

`StatefulPluginService<PKC extends PluginContext>` has a wider bound because it serves both global and session scopes. Bare `extends StatefulPluginService` infers `<PluginContext>`. Two typedef aliases give you the common cases without spelling the generic: `extends SessionStatefulPluginService` for session-scoped (`StatefulPluginService`), `extends GlobalStatefulPluginService` for global-scoped (`StatefulPluginService<GlobalPluginContext>`). Pure syntactic sugar; the explicit form still works.

Plugin helpers (context required, auto-tracked per-context):
- `on<E>(context, handler, {priority, identifier})` returns `EventSubscription`
- `onRequest<R, S>(context, handler, {priority, identifier})` returns `EventSubscription`
- `onRequestSync<R, S>(context, handler, {priority, identifier})` returns `EventSubscription`
- `bind(context, callback)` returns `void Function()` cancel
- `emit<T>(context, event, {identifier})` returns `Future<EventEnvelope<T>>`

StatefulPluginService helpers (no context arg, reads `this.context`, auto-tracked):
- `on<E>(handler, {priority, identifier})` returns `EventSubscription`
- `onRequest<R, S>(handler, {priority, identifier})` returns `EventSubscription`
- `onRequestSync<R, S>(handler, {priority, identifier})` returns `EventSubscription`
- `bind(callback)` returns `void Function()` cancel
- `emit<T>(event, {identifier})` returns `Future<EventEnvelope<T>>`

## Service registry (`service_registry.dart`)

Services registered against a `ServiceId` with a priority. Resolution returns highest-priority enabled wrapper.

Registration from `Plugin.register`:
```dart
void registerCapabilityInPlugin(ScopedServiceRegistry registry) {
  registry.registerSingleton<MyService>(
    const ServiceId('my_service'),
    () => const MyService(),
    capabilities: const {ConfigurableCapability()},
  );
}

bool checkConfigurable(ServiceRegistry registry) {
  return registry
      .resolveRaw<MyService>(const ServiceId('my_service'))
      .capabilities
      .hasType<ConfigurableCapability>();
}
```

`ServiceRegistry.defaultPriority` is `Priority.normal` (500). Higher wins; same polarity in `EventBus`. Named stops: `lowest`/`low`/`normal`/`elevated`/`high`/`system` = 0/100/500/1000/5000/10000.

Wrapper kinds (all take `Factory<T>`):
```
Singleton:      runs ONCE at registration. Same instance on every resolve.
LazySingleton:  runs once on first resolve, cached after. Use for self-referential services that capture the registry.
Factory:        runs on every resolve. Rejects StatefulPluginService (lifecycle requires a tracked instance).
```

Resolution from a context:
```dart
/// Demonstrates request/response patterns on a standalone bus.
///
/// Handlers concede by returning `null` regardless of whether [Response]
/// is nullable. Consumers pick between two methods at the call site:
/// `maybeRequest` (canonical, returns null when nobody answered) and
/// `request` (assertion variant, throws when nobody answered).
Future<void> demonstrateRequestPatterns(PluginContext context) async {
  context.bus.onRequest<SearchQuery, SearchResults>((env) async {
    if (env.event.q.isEmpty) return null; // concede; next handler may claim
    return const SearchResults(results: ['result']);
  });

  // Assertion variant: throws AllConcededException if every handler
  // conceded. Use only when at least one handler is guaranteed to claim.
  final response = await context.bus.request<SearchQuery, SearchResults>(
    const SearchQuery(q: 'dart patterns'),
  );

  // Canonical: returns null when nobody answered.
  final maybe = await context.bus.maybeRequest<SearchQuery, SearchResults>(
    const SearchQuery(),
  );

  // Sync assertion variant: same throws-on-no-answer semantics.
  final sync = context.bus.requestSync<SearchQuery, SearchResults>(
    const SearchQuery(q: 'dart patterns'),
  );

  // Sync canonical: returns null when nobody answered.
  final maybeSync = context.bus.maybeRequestSync<SearchQuery, SearchResults>(
    const SearchQuery(),
  );

  print('$response $maybe $sync $maybeSync');
}
```

Inspection:
```dart
registry.raw.listAllServiceIds([pluginId]);              // Set<ServiceId>
registry.raw.getRegistrations(serviceId);                // List<RegistrationWrapper>?
registry.raw.getAllResolvedRegistrations();              // Map<ServiceId, RegistrationWrapper>
registry.raw.didPluginRegisterServices(pluginId);        // bool
registry.raw.listCapabilitiesOfNamespace(namespace);     // CapabilitySet
```

Capabilities (`capabilities.dart`):

Capability tags attached at registration. Discover features without instantiating the service.

```dart
class ConfigurableCapability extends Capability { const ConfigurableCapability(); }

// In Plugin.register:
registry.registerSingleton<MyService>(serviceId, () => MyService(),
    capabilities: const {ConfigurableCapability()});

// At resolve time:
context.registry.resolveRaw<MyService>(serviceId)
    .capabilities.hasType<ConfigurableCapability>();
```

`CapabilitySet` is `typedef Set<Capability>`. `hasType<T>()` and `getOfType<T>()` are extensions on `Set<Capability>`. `listCapabilitiesOfNamespace(ns)` returns the union over a namespace prefix.

## PluginService base classes (`plugin/service.dart`)

```dart
class ModelRouter extends PluginService {
  String get defaultModel => config.getString('default_model') ?? 'gpt-4';

  @override
  void onSettingsInjected() {
    // Framework has already updated `settings`, `settingsHash`, `config`.
    // React here: re-derive cached values, reconnect upstreams, etc.
  }
}

class ChatService extends StatefulPluginService {
  @override
  void attach() {
    on<UserMessage>((e) => /* ... */);
  }

  @override
  Future<void> detach() async {}
}
```

Signature contracts:
- `Plugin.attach(context)` and `Plugin.detach(context)` take a context arg. No `this.context` on Plugin (instance shared across sessions). Helpers take `context` as first arg.
- `StatefulPluginService.attach()` and `detach()` take no arg. Framework binds and unbinds `this.context` via library-private `_bindContext` / `_unbindContext`. Helpers read `this.context`.

`pluginId` and `serviceId` on `PluginService` are `late` and stamped on first resolve. Don't read them in the constructor.

`config` returns a `ConfigNode` with typed accessors: `getString`, `getInt`, `getDouble`, `getBool`, `list<T>`, `map` (`config_node.dart`). Every accessor returns nullable; chain with `??` for a fallback (`config.list<String>('tags') ?? const ['default']`).

## Event bus (`event_bus.dart`)

Two patterns: cascade (`on` / `emit`) and request/response (`onRequest` / `request`).

Events:
```dart
on<MyEvent>(
  (envelope) => /* ... */,
  priority: Priority.normal, // higher runs first; default is Priority.normal (500)
  identifier: null,          // null matches all; 'foo' scopes
);

final envelope = await emit(MyEvent(...), identifier: null);
envelope.event;          // possibly mutated by handlers
envelope.stopped;        // true if a handler called stop(value)
envelope.identifier;
```

`EventEnvelope.stop(T value)` sets `event` to `value` and marks stopped. Subsequent handlers don't run.

Requests:
```dart
onRequest<RequestType, ResponseType>((envelope) async {
  if (canHandle) return ResponseType(...);
  return null;            // null concedes; next handler tries (works even when Response is non-nullable)
});

final maybe     = await context.bus.maybeRequest<RequestType, ResponseType>(req);   // canonical
final response  = await context.bus.request<RequestType, ResponseType>(req);        // assertion variant; throws on no-answer
final maybeSync = context.bus.maybeRequestSync<RequestType, ResponseType>(req);
final sync      = context.bus.requestSync<RequestType, ResponseType>(req);
```

Handlers concede by returning `null` regardless of whether `Response` is nullable. Pick `maybeRequest` / `maybeRequestSync` (canonical, returns null on no-answer) or `request` / `requestSync` (assertion variant, throws on no-answer; use only when at least one handler is guaranteed to claim).

Failure shape:
- `request` / `requestSync` throw a `NoRequestAnswerException` subtype (`plugin/exceptions.dart`): `RequestNotWiredException` (no handler for the `(Request, Response)` type pair, or handlers exist but none match the requested identifier; carries `wasIdentifierMismatch` to distinguish) or `AllConcededException` (every handler ran and returned null on a non-nullable `Response`; message recommends `maybeRequest`).
- `maybeRequest` / `maybeRequestSync` catch the sealed `NoRequestAnswerException` base and return null. Handler-thrown exceptions propagate unchanged through both methods; `null` from `maybeRequest` means "no one answered," not "a handler crashed." Catch `RequestNotWiredException` / `AllConcededException` separately, or the sealed base, when you need to distinguish at the catch site.

Type-agnostic taps:
```dart
bind(context, (envelope) => log(envelope.event));   // Plugin form
bind((envelope) => log(envelope.event));            // StatefulPluginService form
```

`bind` callbacks see user events emitted via `emit(...)`. Events emitted via `emitInternal(...)` (system lifecycle events) are filtered out by the `internal` flag check, not the envelope type. There is no special envelope class; everything uses plain `EventEnvelope`.

`EventSubscription` is the cancel-only handle returned by every `on*` method on `EventBus`. Most plugin and service code does not touch it directly because `attach`/`detach` orchestration auto-cancels tracked subscriptions; reach for `EventSubscription` only when handing a subscription off to a longer lifecycle (e.g., a custom controller) or when you need to cancel before detach. The `EventBinding` interface (distinct from `EventSubscription`) is a declarative descriptor consumed by the Flutter listener-lifecycle utilities (`PluginSessionStateListener`, `PluginSessionListener`).

Scope routing (sessions):
```dart
context.sessions.emit(...);              // global plugin: broadcast to every session bus
context.sessions.first.bus.emit(...);    // global plugin: target one session
context.globalBus.emit(...);             // session plugin: reach the global bus
```

## RuntimeSettings (`settings.dart`)

```dart
final settingsForJson = RuntimeSettings(
  plugins: {
    const PluginId('chat'): const PluginConfig(
      enabled: true,
      config: {'api_key': 'xxx'},
    ),
    const PluginId('legacy'): const PluginConfig(enabled: false),
  },
  services: {
    Pin('chat', ['agent', 'model']): const ServiceSettings(
      config: {'temperature': 0.7},
    ),
    Pin.wildcard(['agent', 'tools']): const ServiceSettings(
      priority: 200,
      config: {'verbose': true},
    ),
    Pin('legacy', ['search', 'engine']): const ServiceSettings(enabled: false),
  },
);

Map<String, dynamic> roundTripJson() {
  final json = settingsForJson.toJson();
  final back = RuntimeSettings.fromJson(json);
  assert(back.plugins.length == settingsForJson.plugins.length);
  return json;
}
```

`ServiceSettings`: `enabled` (default true), `priority` (overrides registration priority), `config` (`Map<String, dynamic>` injected via `PluginService.injectSettings`).

`const RuntimeSettings(...)` is const-evaluable when every key uses `Pin.fromWire('plugin:service')` and every value (`ServiceSettings(...)`) is const AND every config-map value is const-evaluable. The runtime constructors `Pin(plugin, segments)` / `Pin.wildcard(segments)` and `pluginId.service(...)` join segments at runtime, so settings using them must be `final`. Default to `final` since RuntimeSettings is typically built from JSON anyway; reach for `const` only when configs are fully literal and you want compile-time evaluation.

`const RuntimeSettings()` for an empty settings literal.

## Sessions (`plugin/runtime.dart`)

```dart
final runtime = PluginRuntime(plugins: [/* ... */]);
runtime.init(settings: const RuntimeSettings());

final session = await runtime.createSession(
  settings: const RuntimeSettings(),
  contextFactory: (registry, sessionBus, globalBus) => MySessionContext(
    registry: registry,
    bus: sessionBus,
    globalBus: globalBus,
  ),
);

runtime.isPluginEnabled(pluginId, settings);  // settings-intent (no dep validation)
runtime.attachedGlobalPluginIds;              // dep-validated effective global set
runtime.sessions;                             // List<PluginSession>
runtime.globalRegistry;
runtime.globalBus;

session.enabledPluginIds;                     // dep-validated effective set for this session
session.isPluginEnabled(pluginId);            // bool

await session.dispose();           // detaches all session plugins
await runtime.dispose();           // detaches all global plugins
```

`PluginContext` field is `registry`, not `serviceRegistry`. Test stubs:

```dart
PluginContext.stub();              // base context
GlobalPluginContext.stub();        // includes empty sessions list
SessionPluginContext.stub();       // includes default empty global bus
```

## Runtime (`runtime.dart`)

The lifecycle engine. Holds the current settings snapshot, exposes a stream, and runs serialized reconciliation.

```dart
final runtime = PluginRuntime(plugins: [/* ... */]);
runtime.init(
  settings: const RuntimeSettings(),
  // unknownReferencePolicy: defaults to throwError. Pass logAndSkip on production
  // load paths that read cached settings across app upgrades (renamed/removed ids
  // would otherwise crash startup). See "Validation" below.
);

runtime.settings;                  // current RuntimeSettings snapshot
runtime.settingsStream;            // Stream<RuntimeSettings>; broadcast, no replay

runtime.enabledPlugins;            // Iterable<Plugin> per current settings (settings-intent)
runtime.enabledPluginIds;          // Set<PluginId>
runtime.isPluginEnabled(pluginId); // bool

runtime.attachedPlugins;           // List<Plugin> the runtime actually attached (runtime-effective)
runtime.attachedPluginIds;         // Set<PluginId>
runtime.isPluginAttached(pluginId); // bool

runtime.addPlugin(MyPlugin());     // before init only
runtime.addPlugins([...]);

await runtime.createSession(contextFactory: ...);
await runtime.updateSettings(newSettings);    // serialized: global, then each session
runtime.updateSettingsSnapshot(snapshot);     // emits on stream without reconciling
runtime.resetSettings();
await runtime.dispose();
```

`enabledPlugins` reports settings-intent: locked + explicit settings + experimental heuristic. Does not account for dependency cascade. `attachedPlugins` reports the post-cascade effective set the runtime actually attached. A plugin enabled in settings but cascade-disabled because its dependency is off appears in `enabledPlugins` but not `attachedPlugins`. Use `enabledPlugins` for settings UI; `attachedPlugins` for "is it actually running."

`updateSettings` runs strictly sequentially (global reconcile first, then each session in order) and updates the stored snapshot only after all reconciles complete. If any reconcile throws, the snapshot stays at the previous value.

Re-entry: `updateSettings`, `updateGlobalSettings`, and `updateSessionSettings` share a single `_reconciling` flag and throw `StateError` if invoked while another pass is in flight. Callers must serialize their settings updates (the standard pattern is a tail-chained `Future` per the troubleshooting docs); the docs already required this, the guard makes it loud instead of letting silent interleaving corrupt state.

Validation: every entry point that accepts `RuntimeSettings` runs three passes. Two run upfront: plugin ids in service pin keys (`RuntimeSettings.services`) and plugin ids in plugin config keys (`RuntimeSettings.plugins`). The third runs after register-all and verifies that plugin-scoped pins target a service id the named plugin actually registered (catches renamed/removed slots, not just renamed plugins). Wildcard pins (`Pin.wildcard(...)`) are exempt from the service-id pass by design.

Response to unknown references is configured via `init(unknownReferencePolicy: ...)` using the `UnknownReferencePolicy` enum:
- `throwError` (default): throws `StateError` naming the unknowns. Strict for dev/CI.
- `logAndSkip`: emits one severe log per pass listing the dropped ids; known entries still apply. Use this on production load paths that read cached settings written by a prior app version.
- `ignore`: silent drop; pair with another channel that surfaces drift.

Failure state consistency: on a thrown lifecycle hook during enable, the runtime rolls back the partial registration (unregisters any services the failing plugin registered) and does NOT add the plugin to `enabledPluginIds` / `_enabledGlobalPluginIds`. On a thrown `session.init`, the session is not added to `runtime.sessions`. After catching `PluginLifecycleException`, state queries (`isPluginEnabled`, `isPluginAttached`, `runtime.sessions`) report the actual post-lifecycle truth, not the pre-mutation intent.

Dependency cycles among enabled plugins are detected via Tarjan's SCC and surfaced as `severe` log entries naming the participants. Detection is informational only - the plugins still attach when their mutual dependencies are satisfied. Investigate cycles; they signal coupling that should usually be merged via a shared service.

## Flutter integration (`package:flutter_plugin_kit`)

Separate package; not exported from plugin_kit. Use it instead of holding `_runtime`/`_session` fields and inline `StreamSubscription` plumbing on a Flutter `State`.

Widgets:
- `PluginRuntimeScope({required List<Plugin> plugins, RuntimeSettings? initialSettings, required Widget child})`: scope-owned runtime. Calls `init` in initState, `dispose` in dispose.
- `PluginRuntimeScope.value({required PluginRuntime runtime, required Widget child})`: externally-owned runtime. Scope does not dispose.
- `PluginSessionScope({PluginSession? session, PluginRuntime? runtime, WidgetBuilder? loading, Widget Function(BuildContext, Object)? error, required Widget child})`: at most one of `session`/`runtime`. Resolution order: explicit `session`, then explicit `runtime`, then ambient `PluginRuntimeScope`. Renders `loading` while creating, `error` on creation failure.
- `PluginSessionListener<E>({required Widget Function(BuildContext, EventEnvelope<E>?) builder, ...})`: rebuilds on matching events from the ambient session.
- `PluginEventNotifier<E>(session)`: `ValueListenable<EventEnvelope<E>?>` over the latest event of `E`.

Mixins:
- `PluginSessionStateListener` on `State<W>`: replaces inline `session.on<E>(...)` plumbing. Use `listen<E>(handler)` and `rebuildOn<E>(when:)` in `initState` or `didChangeDependencies`. Tracks bindings, cancels on dispose, re-attaches across session swap.

BuildContext extensions:
- `context.watchEvent<E>()`: subscribes the calling element and returns the latest `EventEnvelope<E>?` from the ambient session. Triggers a rebuild on each new event.
- `context.readEvent<E>()`: one-shot read of the latest envelope without subscribing.

Helper:
- `disposeAndReport(Future<void> Function() dispose, {required String contextDescription})`: wraps an async dispose in `Future<void>.sync(...).catchError(...)` and routes any sync OR async failure through `FlutterError.reportError` tagged with `library: 'flutter_plugin_kit'`. Use it from any `State.dispose` that fires off an async teardown.

Plugin and service code stays the same. The mixins are widget-side adapters; they consume the same `EventBus` and `PluginSession` the Dart-only API exposes.

## Source pointers

- `packages/plugin_kit/lib/src/typed_handles.dart`: typed handles
- `packages/plugin_kit/lib/src/plugin/core.dart`: Plugin base, FeatureFlag
- `packages/plugin_kit/lib/src/plugin/plugin.dart`: GlobalPlugin, SessionPlugin
- `packages/plugin_kit/lib/src/plugin/service.dart`: PluginService, StatefulPluginService, SessionStatefulPluginService / GlobalStatefulPluginService aliases
- `packages/plugin_kit/lib/src/plugin/exceptions.dart`: PluginLifecycleException, PluginStepAggregateException, NoRequestAnswerException (sealed), RequestNotWiredException, AllConcededException
- `packages/plugin_kit/lib/src/plugin/extensions.dart`: helpers
- `packages/plugin_kit/lib/src/types.dart`: PluginContext variants
- `packages/plugin_kit/lib/src/service_registry.dart`: ServiceRegistry, ScopedServiceRegistry
- `packages/plugin_kit/lib/src/event_bus.dart`: EventBus, EventEnvelope, EventBinding
- `packages/plugin_kit/lib/src/settings.dart`: RuntimeSettings, ServiceSettings, PluginConfig
- `packages/plugin_kit/lib/src/plugin/runtime.dart`: PluginRuntime, PluginSession
- `packages/plugin_kit/lib/src/runtime.dart`: PluginRuntime
- `packages/plugin_kit/lib/src/capabilities.dart`: Capability, CapabilitySet
- `packages/plugin_kit/lib/src/config_node.dart`: ConfigNode
- `packages/plugin_kit/lib/src/dialog/`: UI configurability schema, opt-in
- `packages/flutter_plugin_kit/lib/src/`: PluginRuntimeScope, PluginSessionScope, PluginSessionListener, PluginEventNotifier, PluginSessionStateListener, watchEvent/readEvent, disposeAndReport

Runnable examples: `example/villain_lair/bin/01..15_*.dart` (start at `01_hello_lair.dart` for the minimal end-to-end shape), `example/code_editor/`, `example/model_embassy/`, `example/state_garden/`, `example/plugin_kit_dialog_demo/`.
