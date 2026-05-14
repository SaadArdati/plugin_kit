# plugin_kit: Patterns

Six recurring shapes. None mandatory.

## Index

```
one-line debug tap on every event -> Plugin.attach { bind(context, (e) => log(e)); }
session-bound state reacting to events -> StatefulPluginService with on<T> in attach (#3)
additive event-driven slot, all run -> direct subscription at staggered priority
exactly-one-wins event-driven slot -> dispatcher pattern (#1)
service that walks the registry chain -> lazy singleton + closure-captured registry (#2)
per-session service state -> registerSingleton(id, () => T()); externalize for durability (#3)
const-context namespace id -> ServiceId.namespaced(ns, 'id') (#4)
mutate or veto before commit -> mutable draft event + bus.emit returning envelope (#5)
higher-priority service with lower as fallback -> resolveAfter (#6)
```

## 1. Replaceable behavior dispatch

Use when: behavior fires on events AND the contract is exactly-one-wins (higher-priority plugins replace, not run alongside).

Not for additive shapes. If multiple registrants should each contribute (pipeline stages, validators, layered enrichment), use direct subscription at staggered priorities instead.

Pattern: register the behavior as a service in the registry; put a single subscription on a dispatcher (the plugin or one dispatcher service); the dispatcher resolves the winner per event and delegates.

```dart
// CORRECT: Register the redactor as a service; let the registry pick the winner.
class MyRedactionPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_redaction');

  static const serviceId = ServiceId('redactor');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Redactor>(
      serviceId,
      () => _ComplianceRedactor(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    on<UserMessageReceived>(context, (e) {
      final redactor = context.maybeResolve<Redactor>(serviceId);
      if (redactor == null) return;
      e.event.text = redactor.redact(e.event.text);
    });
  }
}

class _ComplianceRedactor implements Redactor {
  @override
  String redact(String input) => input.replaceAll(
    RegExp(r'\bsecret\b', caseSensitive: false),
    '[REDACTED]',
  );
}
```

A second plugin can `registerSingleton<Redactor>(redactorId, () => MyStricterRedactor(), priority: Priority.elevated)` and win automatically. Disable just the redactor via `RuntimeSettings.services` keyed `const PluginId('telemetry').service('telemetry.redactor')`.

The dispatcher subscription is one handler. It does not multiply with competing registrations. The registry decides the winner per resolve.

## 2. Registry capture for self-referential services

Use when: a service must call back into the registry (`resolveAfter` chain, sibling lookup, settings injection involving other services).

Constraint: during `Plugin.register()`, only the scoped registry is in scope; `PluginContext` doesn't exist yet; other plugins may not have registered.

Pattern: capture the registry through a closure thunk; register lazily; defer use until first resolve (after register-all and attach-all complete).

```dart
class EnterpriseRouterPlugin extends GlobalPlugin {
  /// The plugin id for this router.
  static const PluginId id = PluginId('enterprise_router');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<ModelRouter>(
      const ServiceId('model_router'),
      () => EnterpriseRouter(ownerId: id, registryThunk: () => registry.raw),
      priority: Priority.elevated,
    );
  }
}
```

Three details:
- `registerLazySingleton` not `registerSingleton`. Defers construction past register-all.
- `() => registry.raw`: thunk over `.raw`. Resolution lives on raw `ServiceRegistry`; the scoped one is registration-only.
- `ownerId: id` passed in. Plain `implements Foo` classes don't auto-know their owner; only `PluginService` subclasses get identity stamped at resolve.

## 3. Per-session state lifetime

Contract: each session has its own service instance. State never leaks across sessions.

Mechanism: `register()` runs once per session for `SessionPlugin` (once per runtime for `GlobalPlugin`). `registerSingleton<T>(id, Factory<T> create)` runs `create()` once at registration. An inline factory `() => T()` evaluates `T()` fresh per `register()` call, so each session gets its own instance.

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

Within-session disable then enable resets state. Settings reconciliation that flips this plugin off then back on within the same session re-runs `register()`, the constructor evaluates again, the `messages` list is empty. This is the correct semantic; toggle is a fresh start, not a save/restore.

State that must outlive reconciliation: persist externally (file, database, in-memory map keyed by session id). Load during `attach()`. The plugin owns the wire-up to a durable store, not the state itself.

The session id comes from `context.extras`. `PluginRuntime.createSession` and `PluginRuntime.createSession` thread a `Map<String, Object>` through to the context's `extras` field; convention is to write a session id there when state needs to outlive a session lifecycle.

```dart
Future<void> createSessionWithFactory(PluginRuntime runtime) async {
  final session = await runtime.createSession(
    contextFactory: (registry, sessionBus, globalBus) => SessionPluginContext(
      registry: registry,
      bus: sessionBus,
      globalBus: globalBus,
      extras: const {'session_id': 'chat-42'},
    ),
  );

  print('session id: ${session.context.extras['session_id']}');
}
```

For shared state across sessions, prefer `GlobalPlugin`. Sharing from a `SessionPlugin` via `() => _sharedField` works (closure capture is visible at the call site) but `GlobalPlugin`'s one-instance-per-runtime shape says it directly.

## 4. Const vs runtime ServiceId composition

Three composition forms. Not equivalent in const-context.

```
const ServiceId.namespaced(Namespace('agent'), 'model')  // const-evaluable
const ServiceId('agent.model')                            // const-evaluable, structureless
final agent('model')                                      // runtime; variable must be final
```

Reason: extension type instance methods (`Namespace.call`, `Namespace.service`, `Namespace.child`) are not const-evaluable. `ServiceId.namespaced(Namespace, String)` is const because `Namespace implements String` lets the initializer interpolate the namespace value directly.

For runtime composition (most call sites): `final modelId = agent('model');`. `PluginId.service(String)` accepts dotted paths inline too: `const PluginId('chat').service('agent.model')`.

For const contexts (`static const` fields, const `RuntimeSettings` literals): `ServiceId.namespaced(...)` or raw `ServiceId('agent.model')`.

```dart
/// Composing namespaced service ids.
void demonstrateNamespaceComposition() {
  const agent = Namespace('agent');
  final modelId = agent('model');
  final scopeId = agent.child('system_prompt')('scope');

  final settings = RuntimeSettings(
    services: {
      const PluginId('chat').namespace('agent').service('model'):
          const ServiceSettings(config: {'temperature': 0.7}),
    },
  );

  print('$modelId $scopeId ${settings.services.length}');
}

```

## 5. Pre-commit interception

Use when: plugins should mutate, enrich, redact, or veto an action before it commits to the outside world (network call, persisted write, send-to-server).

Pattern: event payload has mutable fields by design. Emit and read the post-cascade envelope back.

```dart
/// A mutable draft event for outgoing messages, allowing handlers to mutate
/// or veto the payload before it is sent.
class DraftOutgoingMessage {
  /// The current text of the draft, mutable by handlers.
  String text;

  /// Metadata attached by handlers.
  final Map<String, String> metadata;

  /// Creates a [DraftOutgoingMessage] with [text].
  DraftOutgoingMessage(this.text) : metadata = {};
}
```

`context.bus.emit(event:)` and the `emit(event)` helper both return `Future<EventEnvelope<T>>`. The helper has positional args; `bus.emit` has named args. Use either.

## 6. Chain-of-responsibility fallback

Use when: a service wants to delegate to the next-priority registration for the same slot.

`registry.resolveAfter<T>(pluginId: self, serviceId: slot)`: walks priority-sorted list, finds the registration owned by `self`, returns the next enabled wrapper. Never returns self. Throws `StateError` if no fallback.

```dart
class BetterDartFormatter extends StatefulPluginService implements Formatter {
  @override
  String format(String path, String input) {
    if (path.endsWith('.dart')) {
      // Our specialty. Format it ourselves.
      return input.trim();
    }
    // Hand off to whichever Formatter would be next in line for this slot.
    return context.registry
        .resolveAfter<Formatter>(pluginId: pluginId, serviceId: serviceId)
        .format(path, input);
  }
}
```

`resolve` would loop: it returns the winner, which is self.

There is no `maybeResolveAfter`. For genuinely optional fallback, wrap the call in a try/catch:

```dart
Formatter? _maybeNext() {
  try {
    return context.registry.resolveAfter<Formatter>(
      pluginId: pluginId,
      serviceId: serviceId,
    );
  } on StateError {
    return null;
  }
}

```

Disabled wrappers in the chain are skipped (per `LocalPluginOverride`). `StateError` only fires when no enabled fallback exists.

