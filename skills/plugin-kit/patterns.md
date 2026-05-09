# plugin_kit: Patterns

Six recurring shapes. None mandatory.

## Index

```
one-line debug tap on every event -> Plugin.attach { bind(context, (e) => log(e)); }
session-bound state reacting to events -> StatefulPluginService with on<T> in attach (#3)
additive event-driven slot, all run -> direct subscription at staggered priority
exactly-one-wins event-driven slot -> dispatcher pattern (#1)
service that walks the registry chain -> lazy singleton + closure-captured registry (#2)
per-session service state -> registerSingleton(id, T()) inline; externalize for durability (#3)
const-context namespace id -> ServiceId.namespaced(ns, 'id') (#4)
mutate or veto before commit -> mutable draft event + bus.emit returning envelope (#5)
higher-priority service with lower as fallback -> resolveAfter (#6)
```

## 1. Replaceable behavior dispatch

Use when: behavior fires on events AND the contract is exactly-one-wins (higher-priority plugins replace, not run alongside).

Not for additive shapes. If multiple registrants should each contribute (pipeline stages, validators, layered enrichment), use direct subscription at staggered priorities instead.

Pattern: register the behavior as a service in the registry; put a single subscription on a dispatcher (the plugin or one dispatcher service); the dispatcher resolves the winner per event and delegates.

```dart
abstract class Redactor {
  String redact(String input);
}

class ComplianceRedactor implements Redactor {
  const ComplianceRedactor();
  @override
  String redact(String input) =>
      input.replaceAll(RegExp(r'\b(?:secret|password)\b', caseSensitive: false), '[REDACTED]');
}

class TelemetryPlugin extends SessionPlugin {
  static const PluginId id = PluginId('telemetry');
  static const ServiceId redactorId = ServiceId('telemetry.redactor');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Redactor>(redactorId, ComplianceRedactor());
  }

  @override
  void attach(SessionPluginContext context) {
    on<UserMessageReceived>(context, (envelope) {
      final redactor = context.maybeResolve<Redactor>(redactorId);
      if (redactor == null) return; // disabled by override
      envelope.event.text = redactor.redact(envelope.event.text);
    });
  }
}
```

A second plugin can `registerSingleton<Redactor>(redactorId, MyStricterRedactor(), priority: 100)` and win automatically. Disable just the redactor via `RuntimeSettings.services` keyed `const PluginId('telemetry').service(const ServiceId('telemetry.redactor'))`.

The dispatcher subscription is one handler. It does not multiply with competing registrations. The registry decides the winner per resolve.

## 2. Registry capture for self-referential services

Use when: a service must call back into the registry (`resolveAfter` chain, sibling lookup, settings injection involving other services).

Constraint: during `Plugin.register()`, only the scoped registry is in scope; `PluginContext` doesn't exist yet; other plugins may not have registered.

Pattern: capture the registry through a closure thunk; register lazily; defer use until first resolve (after register-all and attach-all complete).

```dart
class EnterpriseRouter implements ModelRouter {
  final PluginId ownerId;
  final ServiceRegistry Function() registryThunk;
  EnterpriseRouter({required this.ownerId, required this.registryThunk});

  @override
  String? routeFor(String prompt) {
    if (prompt.toLowerCase().contains('enterprise')) return 'gpt-4-enterprise';
    return registryThunk().resolveAfter<ModelRouter>(
      pluginId: ownerId,
      serviceId: const ServiceId('model_router'),
    ).routeFor(prompt);
  }
}

class EnterpriseRouterPlugin extends GlobalPlugin {
  static const PluginId id = PluginId('enterprise_router');
  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<ModelRouter>(
      const ServiceId('model_router'),
      () => EnterpriseRouter(
        ownerId: id,
        registryThunk: () => registry.raw,
      ),
      priority: 100,
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

Mechanism: `register()` runs once per session for `SessionPlugin` (once per runtime for `GlobalPlugin`). Inline construction means each session evaluates the constructor expression fresh.

```dart
class ChatPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('chat');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ChatService>(
      const ServiceId('chat_service'),
      ChatService(),
    );
  }
}

class ChatService extends StatefulPluginService {
  final List<String> messages = [];

  @override
  void attach() {
    on<UserMessageReceived>((e) async {
      messages.add(e.event.text);
      await emit(BotReply('Heard: ${e.event.text}'));
    });
  }
}
```

Within-session disable then enable resets state. Settings reconciliation that flips this plugin off then back on within the same session re-runs `register()`, the constructor evaluates again, the `messages` list is empty. This is the correct semantic; toggle is a fresh start, not a save/restore.

State that must outlive reconciliation: persist externally (file, database, in-memory map keyed by session id). Load during `attach()`. The plugin owns the wire-up to a durable store, not the state itself.

The session id comes from `context.extras`. `PluginRuntime.createSession` and `PluginRuntime.createSession` thread a `Map<String, Object>` through to the context's `extras` field; convention is to write a session id there when state needs to outlive a session lifecycle.

```dart
final session = await runtime.createSession(
  contextFactory: (registry, sessionBus, globalBus) => SessionPluginContext(
    registry: registry,
    bus: sessionBus,
    globalBus: globalBus,
    extras: const {'session_id': 'chat-42'},
  ),
);

class ChatService extends StatefulPluginService {
  late List<String> messages;

  @override
  void attach() {
    final sessionId = context.extras['session_id'] as String;
    messages = ChatStore.loadMessages(sessionId);
    on<UserMessageReceived>((e) async {
      messages.add(e.event.text);
      ChatStore.saveMessages(sessionId, messages);
      await emit(BotReply('Heard: ${e.event.text}'));
    });
  }
}
```

Sharing across sessions: `registerSingleton(id, _sharedField)` shares one instance across every session that re-runs `register()`. For shared state, prefer `GlobalPlugin`. Sharing from a `SessionPlugin` via captured field is a code smell.

## 4. Const vs runtime ServiceId composition

Three composition forms. Not equivalent in const-context.

```
const ServiceId.namespaced(Namespace('agent'), 'model')  // const-evaluable
const ServiceId('agent.model')                            // const-evaluable, structureless
final agent('model')                                      // runtime; variable must be final
```

Reason: extension type instance methods (`Namespace.call`, `Namespace.service`, `Namespace.child`) are not const-evaluable. `ServiceId.namespaced(Namespace, String)` is const because its constructor uses a String-cast trick.

For runtime composition (most call sites): `final modelId = agent('model');`.

For const contexts (`static const` fields, const `RuntimeSettings` literals): `ServiceId.namespaced(...)` or raw `ServiceId('agent.model')`.

```dart
const Namespace agent = Namespace('agent');
final ServiceId modelId = agent('model');
final ServiceId scopeId = agent.child('system_prompt')('scope');

final RuntimeSettings settings = RuntimeSettings(
  services: {
    const PluginId('chat').namespace('agent').service('model'):
        ServiceSettings(config: {'temperature': 0.7}),
  },
);
```

## 5. Pre-commit interception

Use when: plugins should mutate, enrich, redact, or veto an action before it commits to the outside world (network call, persisted write, send-to-server).

Pattern: event payload has mutable fields by design. Emit and read the post-cascade envelope back.

```dart
class DraftOutgoingMessage {
  String text;
  final Map<String, String> metadata;
  DraftOutgoingMessage(this.text) : metadata = {};
}

on<DraftOutgoingMessage>((envelope) {
  envelope.event.text = expandMacros(envelope.event.text);
  envelope.event.metadata['macros_expanded'] = 'true';
});

final envelope = await context.bus.emit<DraftOutgoingMessage>(
  event: DraftOutgoingMessage(userInput),
);
if (envelope.stopped) return;
await sendToServer(envelope.event);
```

`context.bus.emit(event:)` and the `emit(event)` helper both return `Future<EventEnvelope<T>>`. The helper has positional args; `bus.emit` has named args. Use either.

## 6. Chain-of-responsibility fallback

Use when: a service wants to delegate to the next-priority registration for the same slot.

`registry.resolveAfter<T>(pluginId: self, serviceId: slot)`: walks priority-sorted list, finds the registration owned by `self`, returns the next enabled wrapper. Never returns self. Throws `StateError` if no fallback.

```dart
String? routeFor(String prompt) {
  if (prompt.contains('enterprise')) return 'gpt-4-enterprise';
  return registryThunk()
      .resolveAfter<ModelRouter>(
        pluginId: ownerId,
        serviceId: const ServiceId('model_router'),
      )
      .routeFor(prompt);
}
```

`resolve` would loop: it returns the winner, which is self.

There is no `maybeResolveAfter`. For genuinely optional fallback, wrap:

```dart
String? routeFor(String prompt) {
  if (canHandle(prompt)) return route(prompt);
  try {
    return registryThunk()
        .resolveAfter<ModelRouter>(pluginId: ownerId, serviceId: routerId)
        .routeFor(prompt);
  } on StateError {
    return null;
  }
}
```

Disabled wrappers in the chain are skipped (per `LocalPluginOverride`). `StateError` only fires when no enabled fallback exists.

