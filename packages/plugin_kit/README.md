<p align="center">
  <img src="https://raw.githubusercontent.com/SaadArdati/plugin_kit/main/assets/logo-256.png" width="160" alt="Plugin Kit logo" />
</p>

<p align="center">
  <a href="https://pub.dev/packages/plugin_kit"><img src="https://img.shields.io/pub/v/plugin_kit.svg" alt="pub package" /></a>
  <a href="https://github.com/SaadArdati/plugin_kit/blob/main/packages/plugin_kit/LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg" alt="License: BSD-3-Clause" /></a>
</p>

A Dart plugin runtime for apps that have grown into platforms. Features get real lifecycles. Services get replaceable, prioritized implementations. Sessions stay sealed. Events flow between parts of your app that have never been formally introduced.

It has no opinion about what your app does. It does not know about Flutter, servers, agents, editors, or any particular settings backend. You build those on top. The runtime stays the same.

Three primitives carry the whole library:

- **Service registry**: priority, override, disable, and hot-swap, keyed by typed `ServiceId` handles. Higher priority wins resolution; settings can override or disable per-slot.
- **Event bus**: typed envelope cascade with mutation and stop, plus typed request/response. Handlers can mutate the payload, halt the cascade with a value, or chain through priorities.
- **Plugin lifecycle**: `register` → `attach` → `detach`. Scope is `GlobalPlugin` (one instance per runtime) or `SessionPlugin` (one instance shared across sessions, with per-session service instances).

Plugins are wiring; services are the meat. The plugin class declares an id, registers services, and stays small. Real behavior, anything stateful or configurable or replaceable, lives in services.

Pure Dart. No Flutter. Depends only on `collection`, `logging`, and `meta`.

## When not to use this

If your app has one HTTP client, one auth service, one analytics service, and a few screens that call them, use the boring thing. Plugin Kit earns its weight when behavior needs to be replaced, layered, disabled, overridden, or vetoed while the app is running, and settings have stopped being data your app reads and started being something that actively reshapes the system. The rest of this README assumes you are past that line.

## Quick start

Two plugins claim the same `greeter` slot at different priorities. The runtime resolves the higher-priority winner; the host code never sees the competition.

```dart
class CasualPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('casual');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => CasualGreeter(),
    );
  }
}

class FormalPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('formal');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => FormalGreeter(),
      priority: Priority.elevated, // wins (beats Priority.normal default)
    );
  }
}

Future<void> runGreeterExample() async {
  final runtime = PluginRuntime(plugins: [CasualPlugin(), FormalPlugin()])
    ..init();
  final session = await runtime.createSession();

  final greeter = session.resolve<Greeter>(const ServiceId('greeter'));
  print(greeter.greet('world')); // Good day, world.

  await runtime.dispose();
}
```

The formal plugin wins because it asked for higher priority. The casual plugin's greeter is still registered, sitting at the lower priority, ready to win the moment a settings update lowers the formal plugin or disables it. The call site never branches on the choice.

That move, features owning slots and slots resolving to the current winner, is the vocabulary the rest of the library is built on.

## Less breakable runtime

`attach` / `detach` are framework-enforced, so subscriptions opened in `attach` on a `StatefulPluginService` are tracked and cancelled after `detach` returns. Lifecycle failures aggregate into `PluginLifecycleException` with a named phase rather than being dropped. `enabledPlugins` (settings-intent) and `attachedPlugins` (post-dependency-cascade runtime-truth) are distinct queryable sets, so a plugin with a missing dependency does not silently appear to be running. Reconciliation is transactional: per-plugin attach failures roll back to honest state, and `updateSettings` rolls every reconciled session and the global scope back to the previous snapshot on any mid-loop failure so callers never see split-brain.

## Plugins

A plugin has a unique `PluginId`, optional `dependencies`, optional `featureFlags`, and three lifecycle hooks:

```dart
abstract class Plugin {
  PluginId get pluginId;
  Set<PluginId> get dependencies => const {};
  List<FeatureFlag> get featureFlags => const [];

  void register(ScopedServiceRegistry registry) {}
  void attach(covariant PluginContext context) {}
  Future<void> detach(covariant PluginContext context) async {}

  // Mid-session reactivity: invoked when RuntimeSettings change for a plugin
  // that stays enabled across the change. Override to reconnect, swap models,
  // invalidate caches, etc.
  Future<void> onPluginSettingsChanged(
    covariant PluginContext oldContext,
    covariant PluginContext newContext,
  ) async {}
}
```

Two scopes:

- **`GlobalPlugin`**: registered once during `PluginRuntime.init`, shared across every session.
- **`SessionPlugin`**: attached per session, but the same plugin instance is reused across sessions, so mutable plugin fields are shared unless state lives in services or context.

Both default-context generics are inferred. Write `extends GlobalPlugin` / `extends SessionPlugin` without type arguments unless you need a [custom context subclass](https://plugin-kit-docs.saadodi44.workers.dev/concepts/custom-context/).

## Services

Behavior another plugin should override, settings-tune, or disable belongs in a service. Three base classes; pick by what the behavior actually needs:

| Need | Base class | Registration |
|---|---|---|
| No settings, no events, no lifecycle. | Plain Dart class. | `registerFactory` / `registerSingleton` / `registerLazySingleton` |
| Settings injection from `RuntimeSettings.services`. | `PluginService`. | All three. Override `onSettingsInjected()` to react to changes (no super, no args; read `config` / `settings` directly). |
| Lifecycle, events, or session-bound state. | `StatefulPluginService` (or aliases `SessionStatefulPluginService` / `GlobalStatefulPluginService`). | `registerSingleton` / `registerLazySingleton` only; factories rejected. `attach()`, `detach()`, and `onSettingsInjected()` are pure user hooks (no `super`). Auto-tracked event helpers (`on`, `onRequest`, `bind`, `emit`) read `this.context` implicitly. |

```dart
class ChatThread extends StatefulPluginService {
  /// The accumulated messages for this session.
  final List<Message> messages = [];

  @override
  void attach() {
    on<NewMessage>((e) => messages.add(Message(e.event.text)));
  }

  @override
  Future<void> detach() async {
    messages.clear();
  }
}

```

## Service registry

Priority-based, keyed by typed `ServiceId` handles. Inside a plugin's `register`, the registry is plugin-scoped, so registrations auto-fill `pluginId`.

```dart
// Factory: new instance each resolve.
registry.registerFactory<MyService>(
  const ServiceId('my_service'),
  () => MyServiceImpl(),
);

// Singleton: factory runs ONCE at registration; same instance for every resolve.
registry.registerSingleton<MyService>(
  const ServiceId('my_service'),
  () => MyServiceImpl(),
);

// Lazy singleton: factory runs once on first resolve, cached after.
registry.registerLazySingleton<MyService>(
  const ServiceId('my_service'),
  () => MyServiceImpl(),
);

// Resolve at point of use (so hot-swaps take effect).
final service = context.resolve<MyService>(const ServiceId('my_service'));

// Walk the chain when you want the next-best implementation.
final fallback = context.resolveAfter<MyService>(
  pluginId: const PluginId('primary'),
  serviceId: const ServiceId('my_service'),
);
```

Higher priority wins, in both the registry and the event bus. Default is `Priority.normal` (500). Reach for the named stops on `Priority` (`elevated`, `high`, ...) when you want a discoverable override level, or `Priority.above(other)` / `Priority.below(other)` for relative positioning. Raw ints work too.

Build dotted/namespaced ids with `Namespace`:

```dart
const agent = Namespace('agent');

registry.registerSingleton<Model>(agent('model'), () => GptModel());
registry.registerSingleton<Tools>(agent.child('mcp')('tools'), () => McpTools());

context.resolve<Model>(agent('model'));
```

The registry knows nothing about namespaces; they are pure composition into the `ServiceId` string.

## Event bus

Typed, priority-ordered. Handlers receive an `EventEnvelope<T>`, read or mutate the payload via `e.event`, and call `e.stop(value)` to halt the cascade with a final value. There is one subscription primitive (`on<T>`); a "read-only observer" is just a handler that doesn't mutate.

```dart
Future<void> demonstrateMutateAndStop(EventBus bus) async {
  bus.on<MyEvent>((env) async {
    env.event = env.event.copyWith(modified: true);
  }, priority: 10);

  bus.on<MyEvent>((env) async {
    if (env.event.shouldCancel) env.stop(MyEvent.cancelled);
  });

  final result = await bus.emit<MyEvent>(event: const MyEvent());

  bus.bind((obs) => print('saw ${obs.event}'));

  bus.onRequest<SearchQuery, SearchResults>(
    (req) async => const SearchResults(results: ['r']),
  );

  final results = await bus.request<SearchQuery, SearchResults>(
    const SearchQuery(query: 'dart patterns'),
  );

  print(results.results);
  print(result.event.shouldCancel);
}
```

Pick the right method at the call site. `maybeRequest` / `maybeRequestSync` are canonical: they return `null` when the chain produced no answer (no handler wired, no handler matched the identifier, or every handler conceded). `request` / `requestSync` are the assertion variants: use them only when at least one handler is guaranteed to claim; they throw if the chain bottoms out.

The throws are typed. `request` / `requestSync` raise one of two sealed subtypes of `NoRequestAnswerException`:

- `RequestNotWiredException`: no handler is registered for the `(Request, Response)` type pair, or no handler matched the requested identifier (carries a `wasIdentifierMismatch` bool to distinguish). Almost always a wiring bug; fix by registering a handler.
- `AllConcededException`: every registered handler ran and returned `null` on a non-nullable `Response`. The exception message recommends switching to `maybeRequest`; do that if concession is a valid outcome at your call site.

Handler-thrown exceptions are NOT wrapped. They propagate as-is through both `request` and `maybeRequest`. `maybeRequest` catches only `NoRequestAnswerException` and converts it to `null`. `null` from `maybeRequest` means "no one answered," not "a handler crashed."

**Breaking change (from earlier prototypes):** `RequestUnavailableException` and its `RequestUnavailableReason` enum are replaced by the sealed `NoRequestAnswerException` hierarchy described above. Update `on RequestUnavailableException` clauses to catch the appropriate subtype or the sealed base; replace `reason` enum switches with `is`-checks (or `wasIdentifierMismatch` for the not-wired path).

## Sessions

A session is an isolated execution scope with its own registry, event bus, and context. Open as many as you want. Closing one tears down only its session-scoped plugins and services.

```dart
final session = await runtime.createSession();
// ... use session.bus, session.resolve(...) ...
await session.dispose();
```

`enabledPlugins` is settings-intent (what `RuntimeSettings` says is on); `attachedPlugins` is runtime-effective (what the runtime actually attached after dependency cascade). Use `enabledPlugins` for settings UI; `attachedPlugins` for "is it actually running."

## Settings and reconciliation

`RuntimeSettings` is JSON-serializable top-level configuration. Plugin entries are keyed by `PluginId`; service entries use `Pin` (an extension type wrapping the canonical `'pluginId:serviceId'` wire string). Wildcard overrides apply to whichever plugin currently wins resolution for a given `ServiceId`.

```dart
/// Demonstrates constructing [RuntimeSettings] with [Pin] keys and
/// performing a JSON round-trip.
RuntimeSettings demonstrateSettingsWithPin() {
  final settings = RuntimeSettings(
    plugins: {const PluginId('formal'): const PluginConfig(enabled: false)},
    services: {
      Pin('chat', ['agent', 'model']): const ServiceSettings(
        config: {'temperature': 0.7},
      ),
      Pin.wildcard(['agent', 'tools']): const ServiceSettings(priority: 200),
    },
  );

  // JSON round-trip preserves the wire format ("chat:agent.model", "*:agent.tools").
  final json = settings.toJson();
  final back = RuntimeSettings.fromJson(json);
  return back;
}
```

Hand the runtime a new `RuntimeSettings` and reconciliation runs serialized: newly-enabled plugins `register` then `attach`; staying-enabled plugins receive `onPluginSettingsChanged(oldContext, newContext)`; newly-disabled plugins `detach` and unregister. Plugin instances persist across reconciliation; singleton and lazy-singleton service instances are reused, while factory services are recreated on resolve. Settings persist only after every reconcile succeeds.

## Capabilities

Discover what a service can do without instantiating it. `Capability` is an empty base class; subclass for whatever your app cares about, attach at registration time.

```dart
void registerWithCapabilities(ScopedServiceRegistry registry) {
  registry.registerFactory<MyService>(
    const ServiceId('importer'),
    () => const MyService(),
    capabilities: const {
      SupportsFileFormats({'jsx', 'dart'}),
    },
  );
}

SupportsFileFormats? resolveCapability(ServiceRegistry registry) {
  final wrapper = registry.resolveRaw<MyService>(const ServiceId('importer'));
  return wrapper.capabilities.getOfType<SupportsFileFormats>();
}
```

`UiConfigurableCapability` is a built-in capability that ships with this package (Dart-only declaration of editable fields); the Flutter UI for it lives in `plugin_kit_dialog` so non-Flutter consumers never pull in Flutter.

## Companion packages

State management libraries own presentation state. Plugin Kit owns participation. The two Flutter packages below add the widget plumbing for participation to flow through the tree; they do not replace your state library.

| Package | Adds |
|---|---|
| [`flutter_plugin_kit`](https://pub.dev/packages/flutter_plugin_kit) | `PluginRuntimeScope` and `PluginSessionScope` scope `StatefulWidget`s that provide inherited runtime/session access, a `State` mixin that auto-cancels bus subscriptions across session swaps, a `ChangeNotifier` adapter, and `BuildContext.watchEvent<E>()` / `readEvent<E>()` extensions. |
| [`plugin_kit_dialog`](https://pub.dev/packages/plugin_kit_dialog) | A drop-in three-tab Flutter UI for inspecting and editing any `PluginRuntime`: toggle plugins, edit configurable services, browse the registry. |

Both are optional. The runtime works without them.

## Public API

The canonical surface lives in [dartdoc on pub.dev](https://pub.dev/documentation/plugin_kit/latest/). What follows is a curated index by concern.

```dart
import 'package:plugin_kit/plugin_kit.dart';

// Typed handles
PluginId, ServiceId, Namespace, PluginNamespaced, Pin

// Plugins
GlobalPlugin<G extends GlobalPluginContext>
SessionPlugin<S extends SessionPluginContext>
FeatureFlag                    // .experimental, .locked
PluginContext, GlobalPluginContext, SessionPluginContext

// Services
PluginService                  // settings injection
StatefulPluginService<PKC extends PluginContext>
SessionStatefulPluginService   // alias for StatefulPluginService
GlobalStatefulPluginService    // alias for StatefulPluginService<GlobalPluginContext>

// Runtime
PluginRuntime, PluginSession, PluginRuntime

// Service registry
ServiceRegistry, ScopedServiceRegistry
LocalPluginOverride            // per-resolve scope override

// Event bus
EventBus, EventEnvelope, EventBinding
NoRequestAnswerException        // sealed base
RequestNotWiredException        // subtype: no handler / no identifier match
AllConcededException            // subtype: every handler returned null

// Settings
RuntimeSettings, PluginConfig, ServiceSettings

// Config
ConfigNode

// Capabilities
Capability, CapabilitySet
UiConfigurableCapability       // Dart-only field declaration; UI in plugin_kit_dialog
ConfigField (sealed)           // Text, Multiline, Password, Number, Dropdown<T>, Bool, Group, Extension
```

## Documentation

- **Full docs**: [plugin-kit-docs.saadodi44.workers.dev](https://plugin-kit-docs.saadodi44.workers.dev). Concepts, guides, tutorials, reference.
- **Source**: [github.com/SaadArdati/plugin_kit](https://github.com/SaadArdati/plugin_kit)
- **Examples**: [`example/`](https://github.com/SaadArdati/plugin_kit/tree/main/example) in the repo. `villain_lair/` is a numbered-bin tour through every primitive; `model_embassy/` walks competing providers, capabilities, and reconciliation; `state_garden/` shows the same chat pattern bridged to seven Flutter state-management libraries; `code_editor/` is a full Flutter capstone.

## License

BSD 3-Clause. See [LICENSE](https://github.com/SaadArdati/plugin_kit/blob/main/packages/plugin_kit/LICENSE).
