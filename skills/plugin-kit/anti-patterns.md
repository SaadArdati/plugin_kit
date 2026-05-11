# plugin_kit: Anti-patterns

Code that compiles but breaks composition, lifecycle, or hot-swap. Each: shape, why wrong, fix.

## Red-flag index

Symptom in code -> anti-pattern number.

- Behavior on `Plugin.attach` that other plugins should override, settings-tune, or disable -> #1
- String literal `'foo:bar'` or `'*:foo'`, or `Map<String, _>` for typed-handle keys, near registry/settings code -> #2
- `registry.resolve(...)` or `context.resolve(...)` inside `register()` -> #3
- Plugin helpers without `context` arg (`on(handler)` not `on(context, handler)`) -> #4
- `final svc = context.resolve<X>(...)` cached at attach, used later in handlers -> #5
- `registerSingleton(id, _field)` with a plugin-level captured field -> #6
- `context.bus.on(` inside a `Plugin.attach` or `StatefulPluginService.attach` -> #7
- `resolveByPlugin(...)` or otherwise coupling resolution to a plugin id -> #8
- `PluginId('__pk_*')` literal anywhere outside the library -> #9
- Mutable fields on a fact/notification event -> #10
- `super.attach(...)` or `super.detach(...)` calls in user overrides -> SKILL.md convention #1

## 1. Replaceable behavior on Plugin.attach instead of in a service

Plugin classes register services and contain no behavior. `Plugin.attach` subscriptions are for wiring only (debug taps, internal bridges between services this plugin owns). Behavior another plugin should override, settings-tune, or disable belongs in a service.

<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-direct-subscribe-wrong)" -->
```dart
// WRONG: Multiple plugins subscribing directly to the same event for
// winner-takes-all semantics. All handlers fire; both mutate; result depends
// on registration order.
class MyRedactionPluginWrong extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_redaction_wrong');

  @override
  void attach(SessionPluginContext context) {
    on<UserMessageReceived>(context, (e) {
      // This runs alongside every other subscriber -- not winner-only.
      e.event.text = e.event.text.replaceAll('secret', '[REDACTED]');
    });
  }
}
```

If contract is exactly-one-redactor-wins: every competing plugin's handler runs in addition; both fire; both mutate; result is whichever ran last.

Fix: register the redactor as a service (`registerSingleton<Redactor>(...)`). Either let consumers resolve it directly, or wire one dispatcher subscription that resolves the winner per event. See patterns.md #1.

When direct subscription on multiple registrants IS correct: the slot is additive, not winner-takes-all (formatter pipeline, validator chain, layered enrichment of a draft). Cascade running them all is the desired behavior.

## 2. Hand-typed scoped keys or wildcard sentinels

<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-string-settings-key-wrong)" -->
```dart
// WRONG: Using raw strings as map keys.
// RuntimeSettings.services is Map<Pin, ServiceSettings> -- String keys won't compile.
RuntimeSettings buildWrongSettings() {
  return const RuntimeSettings(
    services: {
      // Use Pin(...) or the typed chain, never raw strings here.
    },
  );
}
```

`RuntimeSettings.services` is `Map<Pin, ServiceSettings>`. The String form is JSON wire format only. String keys won't compile against the typed map; if they did via inference, they would leak the `:` and `*` sentinels into every callsite.

Fix:
<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-string-settings-key-fix)" -->
```dart
// CORRECT: Use the typed chain or Pin constructors.
final correctSettings = RuntimeSettings(
  services: {
    const PluginId('chat').namespace('agent').service('model'):
        const ServiceSettings(config: {'temperature': 0.7}),
    PluginId.wildcard.namespace('agent').service('tools'):
        const ServiceSettings(priority: 200),
  },
);
```

For Dart-side construction, prefer `pluginId.namespace('ns').service('leaf')` for namespaced ids via the typed chain, or `Pin('plugin', ['ns', 'leaf'])` / `Pin.wildcard(['ns', 'leaf'])` for direct construction. The wire format (`'pluginId:serviceId'` / `'*:serviceId'`) is only used in JSON; parse with `Pin.fromWire(String)`.

## 3. Resolving from `register()`

<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-resolve-in-register-wrong)" -->
```dart
// WRONG: Resolving services during register(). At that point, other plugins
// may not have registered yet. The behavior is undefined.
class BadPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('bad_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    // DO NOT do this: resolution order is undefined during register-all.
    final _ = registry.raw.maybeResolve<Logger>(const ServiceId('logger'));
    registry.registerSingleton<Logger>(const ServiceId('my_logger'), Logger());
  }
}
```

Lifecycle is register-all then attach-all. During `register()`, other plugins may not have registered. Resolution from `register()` is undefined behavior.

Fix: defer.
<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-resolve-in-register-fix)" -->
```dart
// CORRECT: Defer resolution via lazy singleton, or resolve in attach.
class GoodPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('good_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    // (a) Lazy + closure capture; resolve when the lazy factory fires.
    registry.registerLazySingleton<Logger>(
      const ServiceId('my_logger'),
      () => registry.raw.resolve<Logger>(const ServiceId('logger')),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    // (b) Resolve in attach or in event handlers.
    final logger = context.resolve<Logger>(const ServiceId('logger'));
    logger.log('good plugin attached');
  }
}
```

Same constraint applies to subscriptions: `register()` runs before any `PluginContext` exists. `on<T>(...)` from `register()` is impossible (no context to bucket under).

## 4. Plugin helpers called without context

```dart
@override
void attach(SessionPluginContext context) {
  on<MyEvent>((e) => /* ... */);  // missing context
}
```

Plugin instances are shared across sessions. No `this.context` exists; storing one would lie when a second session attaches. Plugin helpers (`on`, `onRequest`, `onRequestSync`, `bind`, `emit`) take `PluginContext` as first arg so each subscription is bucketed under the session it belongs to.

Fix: thread `context` from `attach(context)` / `detach(context)` into every helper call.
```dart
@override
void attach(SessionPluginContext context) {
  on<MyEvent>(context, (e) => /* ... */);
  bind(context, (envelope) => log(envelope));
  await emit(context, SomeEvent());
}
```

`StatefulPluginService` is per-session-per-instance (constructed inline in `register()`), so `this.context` is safe and helpers omit the arg.

## 5. Caching resolved instances at attach time

<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-cache-resolution-wrong)" -->
```dart
// WRONG: Caching a resolved service in a field. The cache holds the winner
// at attach time; a higher-priority plugin enabled later is invisible.
class CachingService extends StatefulPluginService {
  Logger? _cachedLogger;

  @override
  void attach() {
    _cachedLogger = context.resolve<Logger>(const ServiceId('logger'));
    on<MyEvent>((e) => _cachedLogger!.log('event'));
  }
}
```

Caches the winner that existed at attach time. Higher-priority plugin enabled later registers a different `Logger`; this code keeps using the old one. Hot-swap silently defeated.

Fix: resolve at point of use.
<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-cache-resolution-fix)" -->
```dart
// CORRECT: Resolve at the point of use. O(1) Map lookup.
class NonCachingService extends StatefulPluginService {
  @override
  void attach() {
    on<MyEvent>((e) {
      final logger = context.resolve<Logger>(const ServiceId('logger'));
      logger.log('event');
    });
  }
}
```

Resolution is O(1) Map lookup plus at most one priority sort. Cost is negligible against the composition lost by caching.

Holding fields for components you registered yourself (your own state) is state ownership, not the same thing.

## 6. Sharing service instances across sessions via captured field

<!-- code-excerpt "example/state_garden/lib/src/chat/chat_plugin.dart (chat-plugin-chat-plugin)" -->
```dart
class ChatPlugin extends SessionPlugin {
  static const PluginId id = PluginId('chat');
  static const ServiceId serviceId = ServiceId('service');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ChatService>(serviceId, ChatService());
  }
}
```

Convention is inline construction in `register()` so each session evaluates the constructor expression fresh. Captured field defeats this: every session resolves the same instance. Session A's `messages` IS session B's. Sealed-session semantics break.

Fix: construct inline.
```dart
registry.registerSingleton<ChatService>(
  const ServiceId('chat'),
  ChatService(),
);
```

For genuinely shared state across sessions, use `GlobalPlugin`. One-instance-per-runtime is its native shape.

## 7. Raw `context.bus.on(...)` instead of the helper

```dart
@override
void attach(SessionPluginContext context) {
  context.bus.on<MyEvent>((e) => /* ... */);
}
```

`EventBus.on` returns a `StreamSubscription` that the bus does not auto-cancel. `PluginHelper` and `StatefulPluginServiceHelper` extensions wrap it: helpers bucket subscriptions per context and the framework cancels them on detach.

Fix:
```dart
on<MyEvent>(context, (e) => /* ... */);  // Plugin: pass context
on<MyEvent>((e) => /* ... */);            // StatefulPluginService: reads this.context
```

Reach for `context.bus.on(...)` only when the subscription's lifetime should NOT match the plugin/service. Rare.

## 8. Coupling to a plugin id for resolution

<!-- code-excerpt "website/snippets/lib/service_registry.dart (service-registry-resolve-after)" -->
```dart
class ChainRouter implements ModelRouter {
  /// The plugin id that owns this router.
  final PluginId ownerId;

  /// Returns the live registry on demand.
  final ServiceRegistry Function() registryThunk;

  /// The service id for resolution delegation.
  final ServiceId routerId;

  /// Creates a [ChainRouter].
  ChainRouter({
    required this.ownerId,
    required this.registryThunk,
    required this.routerId,
  });

  @override
  String? routeFor(String prompt) {
    if (prompt.contains('enterprise')) return 'gpt-4-enterprise';
    return registryThunk()
        .resolveAfter<ModelRouter>(
          pluginId: ownerId,
          serviceId: const ServiceId('model_router'),
        )
        .routeFor(prompt);
  }
}
```

The registry resolves by `ServiceId` and priority decides the winner. There is no `resolveByPlugin` API. Wanting one means coupling to a plugin that may be disabled, replaced, or renamed.

Fix: resolve by `ServiceId`. Let priority and override do their job. The legitimate case for naming a specific plugin is `resolveAfter(pluginId: self, serviceId: slot)`, which is cursor-based skip-self for chain delegation, not "give me their instance."

## 9. PluginId starting with `__pk_`

<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-reserved-plugin-id)" -->
```dart
// WRONG: PluginId values starting with '__pk_' are reserved.
// runtime.addPlugin(ReservedPlugin()); // throws ArgumentError
class ReservedPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_normal_plugin'); // fine

  // Avoid: const PluginId('__pk_internal') -- reserved prefix
}
```

`__pk_` is the reserved prefix for internal sentinels (`PluginId.wildcard.value == '__pk_wildcard__'`, `PluginId.winnerScoped.value == '__pk_winner__'`). `PluginRuntime.addPlugin` rejects any user-supplied id matching that prefix to prevent silent collisions with wildcard service-override resolution.

Fix: pick any other naming. Plugin ids conventionally read as lowercase_snake_case matching the feature.

```dart
PluginId('chat')   // fine
PluginId('my_internal')    // fine
PluginId('_my_internal')   // single-underscore is fine; only '__pk_' is reserved
```

## 10. Mutable fields on a fact event

<!-- code-excerpt "website/snippets/lib/anti_patterns.dart (anti-pattern-mutable-fact-event-wrong)" -->
```dart
// WRONG: Mutating a fact event. Facts are observations of things that already
// happened; mutating them contradicts their semantics.
class ImmutableUserMessage {
  /// The message text.
  final String text;

  /// Creates an [ImmutableUserMessage].
  const ImmutableUserMessage(this.text);
}

void showMutableMistake(PluginContext context) {
  context.bus.on<ImmutableUserMessage>((e) {
    // Trying to mutate a fact event is wrong -- the field is final.
    // e.event.text = e.event.text.toUpperCase(); // compile error
    print(e.event.text);
  });
}

```

Two event categories: facts/notifications (describe what already happened) get final fields; pre-commit drafts (designed for handler interception) get mutable fields. Mutating a fact is a category error; there is nothing to intercept.

Fix: keep fact event fields final. Use mutable fields only for pre-commit drafts.

