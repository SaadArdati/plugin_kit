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
8. Runtime manager (enabled vs attached)
9. Source pointers

## Typed handles (`typed_handles.dart`)

Zero-cost extension types over `String`. At runtime they are the underlying String.

```dart
const PluginId         chatId    = PluginId('chat_manager');
const Namespace        agent     = Namespace('agent');
const ServiceId        modelId   = ServiceId('agent.model');

PluginId.wildcard;        // const PluginId('__pk_wildcard__'); pluginId sentinel for wildcard keys
PluginId.winnerScoped;    // const PluginId('__pk_winner__'); winner-scoped override sentinel

// PluginId values starting with '__pk_' are reserved for sentinels.
// PluginRuntime.addPlugin rejects user-supplied ids with that prefix.

agent.value;                       // 'agent'
agent.child('system_prompt');      // Namespace('agent.system_prompt'), runtime, final
agent.service('model');            // ServiceId('agent.model'), runtime, final
agent('model');                    // shorthand for .service(...)

modelId.value;                     // 'agent.model'
modelId.namespace;                 // Namespace('agent'), full prefix via lastIndexOf
modelId.id;                        // 'model', leaf
modelId.topNamespace;              // Namespace('agent'), first segment via indexOf
ServiceId.namespaced(agent, 'model');  // const-friendly composition

// Pin is the map-key type used by RuntimeSettings.services. Build via the
// typed chain (preserves PluginId / ServiceId types) or directly with strings.
chatId.service(modelId);                                  // wire 'chat_manager:agent.model'
PluginId.wildcard.service(modelId);                       // wire '*:agent.model'
PluginId('chat').namespace('agent').service('model');     // wire 'chat:agent.model'
PluginId('chat').namespace('agent')('model');             // shorthand for .service('model')
PluginId('chat').namespace('agent').child('system_prompt').service('scope');  // wire 'chat:agent.system_prompt.scope'

// Direct (string) construction:
Pin('chat', ['agent', 'model']);          // wire 'chat:agent.model'
Pin('chat', ['greeter']);                 // wire 'chat:greeter' (single segment)
Pin.wildcard(['agent', 'tools']);         // wire '*:agent.tools'

final pin = Pin('chat', ['agent', 'model']);
pin.pluginId;                             // PluginId('chat')
pin.serviceId;                            // ServiceId('agent.model')
pin.isWildcard;                           // false
pin.wire;                                 // 'chat:agent.model'

// Wire-format parse side (used by RuntimeSettings.fromJson; const-evaluable):
const Pin.fromWire('chat_manager:agent.model');
const Pin.fromWire('*:agent.tools');
```

`Namespace.call`, `.service`, `.child` and `PluginId.service`, `PluginId.namespace`, `PluginNamespaced.service`, `.child`, `.call` are runtime helpers. `Pin(plugin, segments)` and `Pin.wildcard(segments)` join segments with `'.'` so both are non-const. `Pin.fromWire(String)` is the only const-friendly constructor. Use it for fully-literal const settings, or accept `final` for typical runtime construction.

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
    registry.registerSingleton<MyService>(const ServiceId('my'), MyService());
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

FeatureFlag (`Plugin.featureFlags`):
- `.locked`: always enabled; cannot be disabled via `RuntimeSettings`.
- `.experimental`: disabled by default; requires opt-in via `RuntimeSettings` or by inclusion in `defaultEnabledPluginIds`.
- Custom flags: `const FeatureFlag('your_string')`. Zero-cost extension type over String.

`PluginRuntimeManager.init(defaultEnabledPluginIds: null)`: every non-experimental plugin is on by default. Non-null: only listed ids are on (experimental is overridden by explicit inclusion).

Scope:
- `GlobalPlugin<G extends GlobalPluginContext>`: one instance per runtime; lifetime equals runtime.
- `SessionPlugin<S extends SessionPluginContext>`: one instance per `pluginId` shared across all sessions; lifetime equals runtime. `attach(S context)` runs once per session attach. Service instances inside are per-session because `register()` runs per-session and inline construction evaluates fresh.

`super.attach()` / `super.detach()` are no-ops on both `Plugin` and `StatefulPluginService`. Don't call them. `super.injectSettings(settings, hash: hash)` IS required when overriding settings injection on `PluginService`.

Default-context generics are inferred. `extends SessionPlugin` infers `<SessionPluginContext>`; `extends GlobalPlugin` infers `<GlobalPluginContext>`; `PluginRuntime` and `PluginRuntimeManager` default to `<GlobalPluginContext, SessionPluginContext>`; `PluginSession` defaults to `<SessionPluginContext>`. Spell the type parameters out only when using a custom context subclass.

`StatefulPluginService<PKC extends PluginContext>` has a wider bound because it serves both global and session scopes. Bare `extends StatefulPluginService` infers `<PluginContext>`. Two typedef aliases give you the common cases without spelling the generic: `extends SessionStatefulPluginService` for session-scoped (`StatefulPluginService<SessionPluginContext>`), `extends GlobalStatefulPluginService` for global-scoped (`StatefulPluginService<GlobalPluginContext>`). Pure syntactic sugar; the explicit form still works.

Plugin helpers (context required, auto-tracked per-context):
- `on<E>(context, handler, {priority, identifier})` returns `StreamSubscription`
- `onRequest<R, S>(context, handler, {priority, identifier})` returns `StreamSubscription`
- `onRequestSync<R, S>(context, handler, {priority, identifier})` returns `StreamSubscription`
- `bind(context, callback)` returns `void Function()` cancel
- `emit<T>(context, event, {identifier})` returns `Future<EventEnvelope<T>>`

StatefulPluginService helpers (no context arg, reads `this.context`, auto-tracked):
- `on<E>(handler, {priority, identifier})` returns `StreamSubscription`
- `onRequest<R, S>(handler, {priority, identifier})` returns `StreamSubscription`
- `onRequestSync<R, S>(handler, {priority, identifier})` returns `StreamSubscription`
- `bind(callback)` returns `void Function()` cancel
- `emit<T>(event, {identifier})` returns `Future<EventEnvelope<T>>`

## Service registry (`service_registry.dart`)

Services registered against a `ServiceId` with a priority. Resolution returns highest-priority enabled wrapper.

Registration from `Plugin.register`:
```dart
registry.registerSingleton<MyService>(serviceId, MyService(), priority: 50);
registry.registerLazySingleton<MyService>(serviceId, MyService.new, priority: 50);
registry.registerFactory<MyService>(serviceId, MyService.new, priority: 50);

// Raw (cross-plugin registration):
registry.raw.registerSingleton<MyService>(
  pluginId: someOtherPluginId,
  serviceId: serviceId,
  instance: MyService(),
  priority: 50,
);
```

`ServiceRegistry.defaultPriority` is 50. Conventional priorities: 25 soft fallback, 50 default, 100 overrides default, 200 authoritative.

Wrapper kinds:
```
Singleton:      constructor runs at registration call (the inline expression). One instance per register() call.
LazySingleton:  constructor runs once on first resolve, then cached. Takes Factory<T>. Use for self-referential services that capture the registry.
Factory:        constructor runs on every resolve. Takes Factory<T>. Cannot register StatefulPluginService here; lifecycle requires a tracked instance.
```

Resolution from a context:
```dart
context.resolve<T>(serviceId);            // throws if missing/disabled
context.maybeResolve<T>(serviceId);       // null if missing/disabled
context.resolveAfter<T>(pluginId: ..., serviceId: ...);  // chain skip-self; throws if no fallback
```

Resolution from raw `ServiceRegistry`:
```dart
registry.raw.resolve<T>(serviceId);
registry.raw.maybeResolve<T>(serviceId);
registry.raw.resolveRaw<T>(serviceId);          // returns RegistrationWrapper, no instantiation
registry.raw.maybeResolveRaw<T>(serviceId);
registry.raw.resolveAfter<T>(pluginId: ..., serviceId: ...);
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
registry.registerSingleton<MyService>(serviceId, MyService(),
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
  void injectSettings(Map<String, dynamic> settings, {String? hash}) {
    super.injectSettings(settings, hash: hash);
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

`config` returns a `ConfigNode` with `getString`, `getInt`, `getDouble`, `getBool`, `getList`, `map` helpers (`config_node.dart`).

## Event bus (`event_bus.dart`)

Two patterns: cascade (`on` / `emit`) and request/response (`onRequest` / `request`).

Events:
```dart
on<MyEvent>(
  (envelope) => /* ... */,
  priority: 0,           // higher = later in ascending cascade
  identifier: null,      // null matches all; 'foo' scopes
);

final envelope = await emit(MyEvent(...), identifier: null);
envelope.event;          // possibly mutated by handlers
envelope.stopped;        // true if a handler called stop(value)
envelope.identifier;
```

`EventEnvelope.stop(T value)` sets `event` to `value` and marks stopped. Subsequent handlers don't run.

Requests:
```dart
onRequest<RequestType, ResponseType?>((envelope) async {
  if (canHandle) return ResponseType(...);
  return null;            // null concedes; next handler tries
});

final response  = await context.bus.request<RequestType, ResponseType?>(req);
final maybe     = await context.bus.maybeRequest<RequestType, ResponseType?>(req);
final sync      = context.bus.requestSync<RequestType, ResponseType>(req);
final maybeSync = context.bus.maybeRequestSync<RequestType, ResponseType?>(req);
```

Nullable `Response` enables fall-through. Non-nullable forces a winner or throws.

Failure shape:
- `request` / `requestSync` throw `RequestUnavailableException` (`plugin/exceptions.dart`) when no handler is registered, or when every registered handler conceded with null on a non-nullable `Response`.
- `maybeRequest` / `maybeRequestSync` convert ONLY that exception to null. Handler-thrown exceptions propagate; `null` means "request unavailable," not "handler crashed." Catch `RequestUnavailableException` to distinguish.

Type-agnostic taps:
```dart
bind(context, (envelope) => log(envelope.event));   // Plugin form
bind((envelope) => log(envelope.event));            // StatefulPluginService form
```

`bind` callbacks see user events. `InternalPluginEventResponse` (runtime-internal request/response plumbing) is filtered out.

`EventBinding<E>` extension type wraps the `StreamSubscription` returned from `on`/`bind` with typed `cancel()`. Most plugin and service code does not touch it directly because `attach`/`detach` orchestration auto-cancels tracked subscriptions; reach for `EventBinding` only when handing a binding off to the Flutter listener-lifecycle utilities (`PluginSessionStateListener`, `PluginSessionListener`) or otherwise managing cancellation outside the lifecycle.

Scope routing (sessions):
```dart
context.sessions.emit(...);              // global plugin: broadcast to every session bus
context.sessions.first.bus.emit(...);    // global plugin: target one session
context.globalBus.emit(...);             // session plugin: reach the global bus
```

## RuntimeSettings (`settings.dart`)

```dart
final settings = RuntimeSettings(
  plugins: {
    const PluginId('chat'): const PluginConfig(enabled: true, config: {'api_key': 'xxx'}),
    const PluginId('legacy'): const PluginConfig(enabled: false),
  },
  services: {
    Pin('chat', ['agent', 'model']):
        ServiceSettings(config: {'temperature': 0.7}),

    Pin.wildcard(['agent', 'tools']):
        ServiceSettings(priority: 200, config: {'verbose': true}),

    Pin('legacy', ['search', 'engine']):
        ServiceSettings(enabled: false),
  },
);

final json = settings.toJson();
final back = RuntimeSettings.fromJson(json);
```

`ServiceSettings`: `enabled` (default true), `priority` (overrides registration priority), `config` (`Map<String, dynamic>` injected via `PluginService.injectSettings`).

`const RuntimeSettings(...)` is const-evaluable when every key uses `Pin.fromWire('plugin:service')` and every value (`ServiceSettings(...)`) is const AND every config-map value is const-evaluable. The runtime constructors `Pin(plugin, segments)` / `Pin.wildcard(segments)` and `pluginId.service(...)` join segments at runtime, so settings using them must be `final`. Default to `final` since RuntimeSettings is typically built from JSON anyway; reach for `const` only when configs are fully literal and you want compile-time evaluation.

`const RuntimeSettings.empty()` for an empty settings literal.

## Sessions (`plugin/runtime.dart`)

```dart
final runtime = PluginRuntime(plugins: [/* ... */]);
runtime.init(settings: const RuntimeSettings.empty());

final session = await runtime.createSession(
  settings: const RuntimeSettings.empty(),
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

session.attachedPluginIds;                    // dep-validated effective set for this session
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

## Runtime manager (`runtime_manager.dart`)

Higher-level wrapper used by most apps. Holds the current settings snapshot, exposes a stream, and runs serialized reconciliation.

```dart
final manager = PluginRuntimeManager(plugins: [/* ... */]);
manager.init(
  initialSettings: const RuntimeSettings.empty(),
  defaultEnabledPluginIds: null,   // null: all on except experimental; non-null: only listed are on
);

manager.runtime;                   // PluginRuntime
manager.settings;                  // current RuntimeSettings snapshot
manager.settingsStream;            // Stream<RuntimeSettings>; broadcast, no replay

manager.enabledPlugins;            // Iterable<Plugin> per current settings (settings-intent)
manager.enabledPluginIds;          // Set<PluginId>
manager.isPluginEnabled(pluginId); // bool

manager.attachedPlugins;           // List<Plugin> the runtime actually attached (runtime-effective)
manager.attachedPluginIds;         // Set<PluginId>
manager.isPluginAttached(pluginId); // bool

manager.addPlugin(MyPlugin());     // before init only
manager.addPlugins([...]);

await manager.createSession(contextFactory: ...);
await manager.updateSettings(newSettings);    // serialized: global, then each session
manager.updateSettingsSnapshot(snapshot);     // emits on stream without reconciling
manager.resetSettings();
await manager.dispose();
```

`enabledPlugins` reports settings-intent: locked + explicit settings + `defaultEnabledPluginIds` whitelist (when non-null) + experimental heuristic. Does not account for dependency cascade. `attachedPlugins` reports the post-cascade effective set the runtime actually attached. A plugin enabled in settings but cascade-disabled because its dependency is off appears in `enabledPlugins` but not `attachedPlugins`. Use `enabledPlugins` for settings UI; `attachedPlugins` for "is it actually running."

`updateSettings` runs strictly sequentially (global reconcile first, then each session in order) and updates the stored snapshot only after all reconciles complete. If any reconcile throws, the snapshot stays at the previous value.

## Flutter integration (`package:flutter_plugin_kit`)

Separate package; not exported from plugin_kit. Use it instead of holding `_manager`/`_session` fields and inline `StreamSubscription` plumbing on a Flutter `State`.

Widgets:
- `PluginRuntimeScope({required List<Plugin> plugins, RuntimeSettings? initialSettings, required Widget child})`: scope-owned manager. Calls `init` in initState, `dispose` in dispose.
- `PluginRuntimeScope.value({required PluginRuntimeManager runtime, required Widget child})`: externally-owned manager. Scope does not dispose.
- `PluginSessionScope({PluginSession? session, PluginRuntimeManager? runtime, WidgetBuilder? loading, Widget Function(BuildContext, Object)? error, required Widget child})`: at most one of `session`/`runtime`. Resolution order: explicit `session`, then explicit `runtime`, then ambient `PluginRuntimeScope`. Renders `loading` while creating, `error` on creation failure.
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
- `packages/plugin_kit/lib/src/plugin/exceptions.dart`: PluginLifecycleException, PluginStepAggregateException, RequestUnavailableException
- `packages/plugin_kit/lib/src/plugin/extensions.dart`: helpers
- `packages/plugin_kit/lib/src/types.dart`: PluginContext variants
- `packages/plugin_kit/lib/src/service_registry.dart`: ServiceRegistry, ScopedServiceRegistry
- `packages/plugin_kit/lib/src/event_bus.dart`: EventBus, EventEnvelope, EventBinding
- `packages/plugin_kit/lib/src/settings.dart`: RuntimeSettings, ServiceSettings, PluginConfig
- `packages/plugin_kit/lib/src/plugin/runtime.dart`: PluginRuntime, PluginSession
- `packages/plugin_kit/lib/src/runtime_manager.dart`: PluginRuntimeManager
- `packages/plugin_kit/lib/src/capabilities.dart`: Capability, CapabilitySet
- `packages/plugin_kit/lib/src/config_node.dart`: ConfigNode
- `packages/plugin_kit/lib/src/dialog/`: UI configurability schema, opt-in
- `packages/flutter_plugin_kit/lib/src/`: PluginRuntimeScope, PluginSessionScope, PluginSessionListener, PluginEventNotifier, PluginSessionStateListener, watchEvent/readEvent, disposeAndReport

Runnable examples: `example/villain_lair/bin/01..15_*.dart` (start at `01_hello_lair.dart` for the minimal end-to-end shape), `example/code_editor/`, `example/model_embassy/`, `example/state_garden/`, `example/plugin_kit_dialog_demo/`.
