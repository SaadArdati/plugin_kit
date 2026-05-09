<p align="center">
  <img src="assets/logo-256.png" width="160" alt="Plugin Kit logo" />
</p>

# Plugin Kit

A powerful, domain-agnostic plugin system for Dart applications.

## Overview

Plugin Kit provides a foundation for building modular, event-driven systems with dynamic service registration,
priority-based resolution, and session management. It can be extended for domain-specific use cases
(e.g., AI agents, UI plugins, service integrations).

Plugins are wiring; services are the meat. The plugin class declares an id, registers services, and stays
small. Real behavior, anything stateful or configurable or replaceable, lives in services. Pick a service
base class (plain Dart class, `PluginService`, or `StatefulPluginService`) by which plugin_kit features the
behavior actually needs.

## Features

- Plugin lifecycle. Register, attach, and detach plugins with global and session scopes.
- Service registry. Priority-based dependency injection with factory, singleton, and lazy patterns.
- Event bus. Typed, priority-ordered event system with request-response support.
- Session management. Isolated execution contexts with scoped registries and event buses.
- Capabilities. Discovery without instantiation.
- Configuration. Type-safe settings access via `ConfigNode`.

## Companion packages

| Package | Purpose |
|---|---|
| [`plugin_kit`](packages/plugin_kit) | Pure-Dart runtime: plugins, services, registry, event bus, settings, capabilities. |
| [`flutter_plugin_kit`](packages/flutter_plugin_kit) | Flutter ergonomics: scope widgets that carry the runtime/session through the tree, a `State` mixin that auto-cancels bus subscriptions, a `ChangeNotifier` adapter, and `BuildContext.watchEvent` / `readEvent` extensions. Optional. |
| [`plugin_kit_dialog`](packages/plugin_kit_dialog) | Drop-in Flutter customization UI on top of any `PluginRuntime`. Optional. |

`plugin_kit` stands alone. The Flutter packages are opt-in: pull them in only when you want their conveniences.

## Installation

```yaml
dependencies:
  plugin_kit: ^1.0.0
  # Optional, Flutter-only:
  flutter_plugin_kit: ^0.1.0
  plugin_kit_dialog: ^0.1.0
```

Check pub.dev (or each package's `pubspec.yaml` in this repo) for the current versions.

## Quick Start

### 1. Create a Plugin

```dart
import 'package:plugin_kit/plugin_kit.dart';

class MyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('my_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<MyService>(
      const ServiceId('my_service'),
      () => MyServiceImpl(),
      priority: 50,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    on<SomeEvent>(context, (e) {
      print('Received event: ${e.event}');
    });
  }
}
```

### 2. Register and Initialize

```dart
// Create runtime manager.
final manager = PluginRuntimeManager(plugins: [
  MyPlugin(),
  AnotherPlugin(),
]);

// Initialize the global scope.
manager.init();
```

### 3. Create Sessions

```dart
// Create a session in a single call.
final session = await manager.runtime.createSession(
  settings: manager.settings,
);

// Use the session.
final service = session.context.resolve<MyService>(const ServiceId('my_service'));
await session.bus.emit<MyEvent>(event: MyEvent(data: 'hello'));

// Cleanup.
await session.dispose();
```

---

## Core Concepts

### Plugins

A plugin is a unit of functionality that registers services and subscribes to events.
Use `GlobalPlugin` for application-lifetime plugins (registered once during
`PluginRuntime.init`, shared across all sessions) and `SessionPlugin` for per-session
plugins (created and destroyed with each session).

Both base classes accept a generic context parameter that defaults to the standard
context for that scope (`GlobalPluginContext` and `SessionPluginContext`). Write
`extends SessionPlugin`, `extends GlobalPlugin`, `PluginRuntime`,
`PluginRuntimeManager`, and `PluginSession` without type arguments unless your app
uses a custom context subclass (see [Custom Context](https://plugin-kit-docs.saadodi44.workers.dev/concepts/custom-context/)).

`StatefulPluginService` ships with two ergonomic typedef aliases:
`SessionStatefulPluginService` (for session-scoped services) and
`GlobalStatefulPluginService` (for global-scoped services). They are pure
syntactic sugar; `extends StatefulPluginService<SessionPluginContext>` and
`extends SessionStatefulPluginService` are equivalent at runtime. Use the
explicit form when working with a custom context subclass.

```dart
abstract class Plugin {
  PluginId get pluginId;
  Set<PluginId> get dependencies => const {};
  List<FeatureFlag> get featureFlags => const [];

  void register(ScopedServiceRegistry registry) {}

  void attach(covariant PluginContext context) {}
  Future<void> detach(covariant PluginContext context) async {}

  // Mid-session reactivity. Called when RuntimeSettings change for a
  // plugin that stays enabled across the change. Override to
  // reconnect, swap models, invalidate caches, etc.
  Future<void> onPluginSettingsChanged(
    covariant PluginContext oldContext,
    covariant PluginContext newContext,
  ) async {}
}
```

### Service Registry

Priority-based dependency injection container. Inside a plugin's `register`,
the registry is plugin-scoped (a `ScopedServiceRegistry`), so registrations
auto-fill `pluginId`.

```dart
// Factory: new instance each resolve.
registry.registerFactory<MyService>(
  const ServiceId('my_service'),
  () => MyServiceImpl(),
  priority: 50,
);

// Singleton: same instance always.
registry.registerSingleton<MyService>(
  const ServiceId('my_service'),
  MyServiceImpl(),
);

// Lazy singleton: created on first resolve.
registry.registerLazySingleton<MyService>(
  const ServiceId('my_service'),
  () => MyServiceImpl(),
);

// Resolution.
final service = context.resolve<MyService>(const ServiceId('my_service'));

// Namespaced resolution: build the ServiceId via Namespace.
const ns = Namespace('namespace');
final namespaced = context.resolve<MyService>(ns('slot'));
```

Priority system:

- Higher priority values win when multiple plugins register the same service id.
- Default priority is `50` (`ServiceRegistry.defaultPriority`).
- Use a higher priority to override services from other plugins; a lower one to register a fallback that only wins when nothing else does.

### Event Bus

Typed, priority-ordered event system. Handlers receive an `EventEnvelope<T>`,
read or mutate the payload via `e.event`, and call `e.stop(value)` to halt the
cascade with a final value. There is one subscription primitive (`on<T>`); a
"read-only observer" is just a handler that doesn't mutate.

```dart
// Subscribe. Higher priority runs later in the ascending cascade.
bus.on<MyEvent>((e) async {
  e.event = e.event.copyWith(modified: true);
}, priority: 10);

// Stop the cascade with a final value.
bus.on<MyEvent>((e) async {
  if (shouldCancel) e.stop(MyEvent.cancelled());
});

// Tap-everything callback (auto-tracked when called via the helper).
bus.bind((envelope) {
  print('saw ${envelope.event}');
});

// Emit. Returns the (possibly mutated, possibly stopped) envelope.
final envelope = await bus.emit<MyEvent>(event: MyEvent());

// Request / response.
bus.onRequest<MyRequest, MyResponse>((req) async {
  return MyResponse(data: 'result');
});

final response = await bus.request<MyRequest, MyResponse>(
  MyRequest(query: 'test'),
);
```

Event priority:

- Default priority is 0. Higher numbers run later in the ascending cascade.
- A handler stops the cascade by calling `e.stop(replacementValue)`. The
  emitter sees `envelope.stopped == true` and `envelope.event == replacementValue`.

### Plugin Services

Services with automatic settings injection:

```dart
abstract class PluginService {
  late PluginId pluginId;    // Stamped by the registry on resolve.
  late ServiceId serviceId;
  ConfigNode config;

  // The one method that does require super. Override to react to settings
  // changes (invalidate caches etc.); always call super.injectSettings(...).
  @mustCallSuper
  void injectSettings(Map<String, dynamic> settings, {String? hash});
}

abstract class StatefulPluginService<PKC extends PluginContext>
    extends PluginService {
  // Bound by the framework before attach() runs; cleared after detach() returns.
  PKC get context;

  void attach() {}
  Future<void> detach() async {}
}
```

Example:

```dart
class ChatManager extends StatefulPluginService {
  final List<Message> messages = [];

  @override
  void attach() {
    on<NewMessage>((event) {
      messages.add(event.event);
    });
  }

  @override
  Future<void> detach() async {
    messages.clear();
  }
}
```

### Capabilities

Discover service features without instantiation. `Capability` is an empty
base class; define whatever subclasses your app needs and attach them at
registration time.

```dart
class SupportsFileFormats extends Capability {
  final Set<String> extensions;
  const SupportsFileFormats(this.extensions);
}

// Register with capabilities.
registry.registerFactory<MyService>(
  const ServiceId('my_service'),
  () => MyServiceImpl(),
  capabilities: {
    const SupportsFileFormats({'jsx', 'dart'}),
  },
);

// Discover without constructing the service.
final wrapper = registry.resolveRaw(const ServiceId('my_service'));
final formats = wrapper.capabilities.getOfType<SupportsFileFormats>();
print('supports: ${formats?.extensions}');
```

### Configuration

Type-safe settings access via `ConfigNode`:

```dart
final config = ConfigNode({
  'verbose': true,
  'temperature': 0.7,
  'tools': ['read', 'write'],
});

final verbose = config.getBool('verbose') ?? false;
final temp = config.getDouble('temperature') ?? 0.5;
final tools = config.list<String>('tools') ?? [];

if (config.has('nested')) {
  final nested = config.map('nested');
}
```

### Runtime Settings

Top-level serializable configuration. Plugin entries are keyed by `PluginId`;
service entries use `Pin` — an extension type wrapping the canonical
`'pluginId:serviceId'` wire string. Wildcard overrides apply to whichever
plugin currently wins resolution for that `ServiceId` (`Pin.wildcard(...)`).

```dart
class RuntimeSettings {
  final Map<PluginId, PluginConfig> plugins;
  final Map<Pin, ServiceSettings> services;
}

final settings = RuntimeSettings(
  plugins: {
    const PluginId('chat'): const PluginConfig(enabled: true),
  },
  services: {
    // Plugin-scoped override: tunes the chat plugin's agent.model service.
    Pin('chat', ['agent', 'model']):
        ServiceSettings(config: {'temperature': 0.7}),

    // Wildcard: applies to whichever plugin wins agent.tools resolution.
    Pin.wildcard(['agent', 'tools']):
        ServiceSettings(priority: 200),
  },
);

// JSON round-trip preserves the wire format ("chat:agent.model", "*:agent.tools").
final json = settings.toJson();
final back = RuntimeSettings.fromJson(json);
```

The string form (`'chat:agent.model'`, `'*:agent.tools'`) is for the JSON wire
format only. Inside Dart code, build keys with `Pin('plugin', ['service',
'segments'])` and `Pin.wildcard(['service', 'segments'])`, or via the typed
chain `pluginId.service(serviceId)` / `pluginId.namespace('ns').service('leaf')`.
Hand-typed string keys won't satisfy the typed `Map<Pin, ServiceSettings>`.
Use `Pin.fromWire(String)` only when parsing the wire format yourself
(e.g., implementing a custom JSON path).

---

## File Structure

| File | Purpose |
|------|---------|
| `lib/plugin_kit.dart` | Main export barrel |
| `lib/src/plugin/core.dart` | `Plugin` base, `FeatureFlag`, `Disposer` |
| `lib/src/plugin/plugin.dart` | `GlobalPlugin`, `SessionPlugin` variants |
| `lib/src/plugin/runtime.dart` | `PluginRuntime`, `PluginSession` |
| `lib/src/plugin/service.dart` | `PluginService`, `StatefulPluginService` |
| `lib/src/plugin/extensions.dart` | Plugin / Service / Session helpers (`on`, `emit`, `bind`, `resolve`) |
| `lib/src/runtime_manager.dart` | `PluginRuntimeManager` (settings streaming, optional) |
| `lib/src/types.dart` | `PluginContext`, `GlobalPluginContext`, `SessionPluginContext` |
| `lib/src/typed_handles.dart` | `PluginId`, `ServiceId`, `Namespace`, `PluginNamespaced`, `Pin` |
| `lib/src/event_bus.dart` | `EventBus`, `EventEnvelope` |
| `lib/src/service_registry.dart` | `ServiceRegistry`, `ScopedServiceRegistry`, `LocalPluginOverride` |
| `lib/src/settings.dart` | `RuntimeSettings`, `PluginConfig`, `ServiceSettings` |
| `lib/src/config_node.dart` | `ConfigNode` for type-safe config access |
| `lib/src/capabilities.dart` | `Capability`, `CapabilitySet` |
| `lib/src/dialog/` | UI configurability schema (opt-in) |

---

## Plugin Lifecycle

### Initialization

```dart
// 1. Create the manager with all plugins.
final manager = PluginRuntimeManager(plugins: [Plugin1(), Plugin2()]);

// 2. Initialize the global scope.
manager.init(
  initialSettings: savedSettings,
  defaultEnabledPluginIds: nonExperimentalPluginIds,
);
```

### Session Creation

```dart
// Create a session in a single call.
final session = await manager.runtime.createSession(
  settings: manager.settings,
);

// Use the session.
await session.bus.emit<ReadyEvent>(event: ReadyEvent());
```

### Disposal

```dart
await session.dispose();
```

---

## Advanced Usage

### Priority Override

Override services from other plugins:

```dart
// Core plugin registers with priority 0.
class CorePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('core');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<FileService>(
      const ServiceId('file_service'),
      () => BasicFileService(),
      priority: 0,
    );
  }
}

// Custom plugin overrides with priority 100 - wins resolution.
class CustomPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('custom');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<FileService>(
      const ServiceId('file_service'),
      () => AdvancedFileService(),
      priority: 100,
    );
  }
}
```

### Fallback Resolution

```dart
// Resolve the next service in the priority chain after a given pluginId.
final fallback = registry.resolveAfter<MyService>(
  pluginId: const PluginId('primary_plugin'),
  serviceId: const ServiceId('my_service'),
);
```

### Namespaced Services

```dart
// Build a namespaced ServiceId via Namespace and pass it to the regular
// register / resolve methods. The registry only knows about ServiceId; the
// Namespace is just a convenience for composing dotted ids.
const mainAgent = Namespace('main_agent');

// Register namespaced.
registry.registerFactory<AgentConfig>(
  mainAgent('config'),       // call() shorthand → ServiceId('main_agent.config')
  () => AgentConfig(),
);

// Resolve namespaced.
final config = registry.resolve<AgentConfig>(mainAgent('config'));
```

### Event Request-Response

```dart
// Handler side.
bus.onRequest<PermissionRequest, bool>((request) async {
  return await showDialog(request.action);
});

// Requester side.
final allowed = await bus.request<PermissionRequest, bool>(
  PermissionRequest(action: 'delete_file'),
);
if (allowed) {
  // Proceed.
}
```

---

## Dependencies

```yaml
dependencies:
  collection: ^1.19.1
  meta: ">=1.17.0 <2.0.0"
```

---

## License

Copyright (c) Codelessly. All rights reserved.
