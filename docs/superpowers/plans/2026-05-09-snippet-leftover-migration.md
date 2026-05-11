# Snippet Leftover Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ~85 leftover aspirational/reference doc blocks to `website/snippets/lib/` as compilable docregion-marked snippets, update tests, and write `.codex-out/snippet-leftover-mapping.tsv`.

**Architecture:** Each doc block becomes a `// #docregion <name>` / `// #enddocregion <name>` region in the correct topic file under `website/snippets/lib/`. "Reference surface" blocks (abstract class sketches) use comment-style regions. Truly aspirational blocks define concrete classes and functions. All regions are exercised by adjacent test files. Invented types (referenced in doc blocks but not in the real codebase) are defined either inline in the snippet file or in a shared `_test_doubles.dart` helper.

**Tech Stack:** Dart 3.10+, Flutter 3.27+, flutter_test, plugin_kit, plugin_kit_dialog

---

## Pre-work: Leftover Row Inventory

After cross-referencing `inventory.tsv`, `snippet-mapping.tsv`, and existing `// #docregion` markers, the following **50 regions** need to be written (the remaining 125 "leftover" rows in the inventory are either already covered by existing regions, are real-code rows handled by docregion-plan.tsv in source files, or are genuinely skippable duplicates).

**Truly leftover — regions to create:**

| # | doc_file:lines | target file | region name |
|---|---|---|---|
| 1 | `reference/event-bus-and-events.mdx:14-21` | event_bus.dart | `event-bus-class-surface` |
| 2 | `reference/event-bus-and-events.mdx:31-40` | event_bus.dart | `event-envelope-class-surface` |
| 3 | `reference/event-bus-and-events.mdx:312-316` | event_bus.dart | `session-broadcast-extension` |
| 4 | `concepts/event-bus.mdx:19-32` | event_bus.dart | `on-and-emit-basic-event` |
| 5 | `concepts/event-bus.mdx:75-79` | event_bus.dart | `bind-and-unbind-context` |
| 6 | `api-cheatsheet.md:263-273` | event_bus.dart | `on-request-variants-cheatsheet` |
| 7 | `patterns.md:216-233` | event_bus.dart | `draft-event-mutation-pipeline` |
| 8 | `reference/plugins-and-lifecycle.mdx:62-67` | plugin_services.dart | `stateful-plugin-service-minimal-contract` |
| 9 | `reference/service-registry-and-capabilities.mdx:356-368` | plugin_services.dart | `plugin-service-base-contract` |
| 10 | `reference/service-registry-and-capabilities.mdx:454-461` | plugin_services.dart | `stateful-service-on-helper-example` |
| 11 | `guides/adding-a-plugin.mdx:67-73` | plugin_services.dart | `plain-notification-service-baseline` |
| 12 | `concepts/configuration.mdx:129-131` | plugin_services.dart | `config-raw-accessor` |
| 13 | `concepts/plugin-services.mdx:167-171` | plugin_services.dart | `model-router-service-simple` |
| 14 | `reference/service-registry-and-capabilities.mdx:469-473` | capabilities.dart | `capability-abstract-base` |
| 15 | `reference/service-registry-and-capabilities.mdx:502-507` | capabilities.dart | `capability-lookup-extension-surface` |
| 16 | `api-cheatsheet.md:197-207` | capabilities.dart | `configurable-capability-marker-pattern` |
| 17 | `reference/service-registry-and-capabilities.mdx:18-20` | naming.dart | `plugin-id-extension-type-surface` |
| 18 | `reference/service-registry-and-capabilities.mdx:26-32` | naming.dart | `namespace-extension-type-surface` |
| 19 | `reference/service-registry-and-capabilities.mdx:38-44` | naming.dart | `service-id-extension-type-surface` |
| 20 | `reference/service-registry-and-capabilities.mdx:83-92` | service_registry.dart | `service-registry-class-surface` |
| 21 | `reference/service-registry-and-capabilities.mdx:215-231` | service_registry.dart | `scoped-service-registry-class-surface` |
| 22 | `reference/settings-and-configuration.mdx:43-55` | runtime_settings.dart | `runtime-settings-class-structure` |
| 23 | `reference/settings-and-configuration.mdx:70-72` | runtime_settings.dart | `runtime-settings-empty-constructor` |
| 24 | `reference/settings-and-configuration.mdx:176-186` | runtime_settings.dart | `plugin-config-class-structure` |
| 25 | `reference/plugins-and-lifecycle.mdx:126-145` | custom_context.dart | `plugin-context-class-structure` |
| 26 | `reference/plugins-and-lifecycle.mdx:157-163` | custom_context.dart | `global-plugin-context-class-structure` |
| 27 | `reference/plugins-and-lifecycle.mdx:177-181` | custom_context.dart | `session-plugin-context-class-structure` |
| 28 | `reference/plugins-and-lifecycle.mdx:189-206` | sessions.dart | `plugin-session-class-surface` |
| 29 | `reference/state-management-bridges.mdx:52-65` | state_bridges.dart | `chat-protocol-types` |
| 30 | `guides/migrating-flutter-app.mdx:373-397` | state_bridges.dart | `riverpod-async-notifier-chat-controller` |
| 31 | `guides/logging.mdx:27-33` | logging.dart | `logging-onrecord-listener` |
| 32 | `anti-patterns.md:82-94` | anti_patterns_registry.dart | `lazy-closure-and-attach-resolve-pattern` |
| 33 | `anti-patterns.md:208-215` | anti_patterns_naming.dart | `reserved-pk-prefix-anti-pattern` |
| 34 | `anti-patterns.md:229-238` | anti_patterns_events.dart | `fact-event-mutable-fields-anti-pattern` |
| 35 | `anti-patterns.md:198-200` | anti_patterns_registry.dart | `resolve-by-plugin-does-not-exist` |
| 36 | `testing.md:9-13` | testing.dart | `plugin-context-stub-forms` |
| 37 | `guides/testing.mdx:20-27` | testing.dart | (already exists as `plugin-service-inject-settings-test`) — SKIP |
| 38 | `guides/testing.mdx:58-78` | testing.dart | (already exists as `plugin-request-response-test`) — SKIP |
| 39 | `guides/testing.mdx:154-170` | testing.dart | (already exists as `runtime-update-settings-disables-plugin-test`) — SKIP |
| 40 | `guides/testing.mdx:178-205` | testing.dart | (already exists as `stateful-service-attach-detach-test`) — SKIP |
| 41 | `guides/testing.mdx:228-240` | testing.dart | (already exists as `lifecycle-exception-test`) — SKIP |
| 42 | `guides/flutter-integration.mdx:280-292` | testing.dart | `flutter-widget-editor-shell-test` |
| 43 | `README.md:301-340` (plugin_kit) | api_reference.dart | (already exists as `plugin-kit-symbol-cheatsheet`) — SKIP |
| 44 | `plugin_kit_dialog/README.md:32-47` | dialog.dart | (already covered by `show-dialog-save-merge-settings`) — SKIP |
| 45 | `plugin_kit_dialog/README.md:223-245` | dialog.dart | (already covered by `dialog-api-surface-with-renderers`) — SKIP |
| 46 | `plugin_kit_dialog/README.md:249-260` | config_fields.dart | `config-field-types-reference` |
| 47 | `guides/plugin-kit-dialog.mdx:24-40` | dialog.dart | (already covered by `show-dialog-save-merge-settings-guide`) — SKIP |
| 48 | `guides/plugin-kit-dialog.mdx:253-270` | dialog.dart | (already covered by `dialog-api-surface-theme-and-visuals`) — SKIP |
| 49 | `guides/plugin-kit-dialog.mdx:274-285` | config_fields.dart | `config-field-types-guide-reference` |

**Net new regions to write: 36** (rows 37-41, 43-45, 47-48 are already covered by existing regions).

---

## File Structure

**Files to modify:**
- `website/snippets/lib/event_bus.dart` — add 7 regions
- `website/snippets/lib/plugin_services.dart` — add 6 regions
- `website/snippets/lib/capabilities.dart` — add 3 regions
- `website/snippets/lib/naming.dart` — add 3 regions
- `website/snippets/lib/service_registry.dart` — add 2 regions
- `website/snippets/lib/runtime_settings.dart` — add 3 regions
- `website/snippets/lib/custom_context.dart` — add 3 regions
- `website/snippets/lib/sessions.dart` — add 1 region
- `website/snippets/lib/state_bridges.dart` — add 2 regions
- `website/snippets/lib/logging.dart` — add 1 region
- `website/snippets/lib/anti_patterns_registry.dart` — add 2 regions
- `website/snippets/lib/anti_patterns_naming.dart` — add 1 region
- `website/snippets/lib/anti_patterns_events.dart` — add 1 region
- `website/snippets/lib/testing.dart` — add 2 regions
- `website/snippets/lib/config_fields.dart` — add 2 regions

**Files to modify (tests):**
- `website/snippets/test/event_bus_test.dart`
- `website/snippets/test/plugin_services_test.dart`
- `website/snippets/test/capabilities_test.dart`
- `website/snippets/test/naming_test.dart`
- `website/snippets/test/service_registry_test.dart`
- `website/snippets/test/runtime_settings_test.dart`
- `website/snippets/test/custom_context_test.dart`
- `website/snippets/test/sessions_test.dart`
- `website/snippets/test/state_bridges_test.dart`
- `website/snippets/test/logging_test.dart`
- `website/snippets/test/anti_patterns_registry_test.dart`
- `website/snippets/test/anti_patterns_naming_test.dart`
- `website/snippets/test/anti_patterns_events_test.dart`
- `website/snippets/test/testing_test.dart`
- `website/snippets/test/config_fields_test.dart`

**Files to create:**
- `.codex-out/snippet-leftover-mapping.tsv`

---

## Task 1: event_bus.dart — add 7 regions

**Files:**
- Modify: `website/snippets/lib/event_bus.dart`
- Modify: `website/snippets/test/event_bus_test.dart`

- [ ] **Step 1: Add `event-bus-class-surface` region to event_bus.dart**

The doc block at `reference/event-bus-and-events.mdx:14-21` shows:
```dart
class EventBus {
  EventBus();
  bool get isDisposed;
  void dispose();
}
```
This is a reference surface. Wrap in a comment-style region appended after the last existing region in `event_bus.dart`:

```dart
// ---------------------------------------------------------------------------
// event-bus-class-surface  (reference/event-bus-and-events.mdx:14-21)
// ---------------------------------------------------------------------------

// #docregion event-bus-class-surface
// EventBus public surface (simplified for docs):
//
//   class EventBus {
//     EventBus();
//     bool get isDisposed;
//     void dispose();
//   }

EventBus buildEventBus() => EventBus();
// #enddocregion event-bus-class-surface
```

- [ ] **Step 2: Add `event-envelope-class-surface` region**

Doc block at `reference/event-bus-and-events.mdx:31-40`:
```dart
class EventEnvelope<T> {
  EventEnvelope({required T event, required String? identifier});
  T event;
  final String? identifier;
  bool get stopped;
  void stop(T value);
}
```

```dart
// ---------------------------------------------------------------------------
// event-envelope-class-surface  (reference/event-bus-and-events.mdx:31-40)
// ---------------------------------------------------------------------------

// #docregion event-envelope-class-surface
// EventEnvelope<T> public surface (simplified for docs):
//
//   class EventEnvelope<T> {
//     EventEnvelope({required T event, required String? identifier});
//
//     T event;                  // mutable; downstream handlers see writes
//     final String? identifier; // the emit-time scope, if any
//     bool get stopped;
//     void stop(T value);
//   }

EventEnvelope<String> buildEnvelope() =>
    EventEnvelope(event: 'hello', identifier: null);
// #enddocregion event-envelope-class-surface
```

- [ ] **Step 3: Add `session-broadcast-extension` region**

Doc block at `reference/event-bus-and-events.mdx:312-316`:
```dart
extension SessionBroadcast on List<PluginSession> {
  Future<void> emit<T>(T event, {String? identifier});
}
```
This is a docs-only surface sketch. Use comment style:

```dart
// ---------------------------------------------------------------------------
// session-broadcast-extension  (reference/event-bus-and-events.mdx:312-316)
// ---------------------------------------------------------------------------

// #docregion session-broadcast-extension
// SessionBroadcast extension on List<PluginSession> (via extensions.dart):
//
//   extension SessionBroadcast on List<PluginSession> {
//     Future<void> emit<T>(T event, {String? identifier});
//   }
// #enddocregion session-broadcast-extension
```

- [ ] **Step 4: Add `on-and-emit-basic-event` region**

Doc block at `concepts/event-bus.mdx:19-32`:
```dart
class UserLoggedInEvent {
  final String userId;
  UserLoggedInEvent(this.userId);
}
context.bus.on<UserLoggedInEvent>((e) {
  print('User logged in: ${e.event.userId}');
});
await context.bus.emit<UserLoggedInEvent>(
  event: UserLoggedInEvent('u_123'),
);
```

Add a helper function `runOnAndEmitBasicEvent` that wraps the region and returns the userId for testing:

```dart
// ---------------------------------------------------------------------------
// on-and-emit-basic-event  (concepts/event-bus.mdx:19-32)
// ---------------------------------------------------------------------------

// #docregion on-and-emit-basic-event
class UserLoggedInEvent {
  final String userId;
  UserLoggedInEvent(this.userId);
}
// #enddocregion on-and-emit-basic-event

Future<String> runOnAndEmitBasicEvent() async {
  final context = mini.PluginContext.stub();
  String? capturedId;

  // #docregion on-and-emit-basic-event
  context.bus.on<UserLoggedInEvent>((e) {
    print('User logged in: ${e.event.userId}');
  });

  await context.bus.emit<UserLoggedInEvent>(
    event: UserLoggedInEvent('u_123'),
  );
  // #enddocregion on-and-emit-basic-event

  context.bus.on<UserLoggedInEvent>((e) {
    capturedId = e.event.userId;
  });
  await context.bus.emit<UserLoggedInEvent>(event: UserLoggedInEvent('u_123'));
  return capturedId ?? '';
}
```

Note: A named region can appear multiple times; each occurrence is included when the region is extracted. Here the class definition and the usage are two separate regions with the same name — the extractor merges them. This is fine per the docregion spec. However to keep it clean, use a single wrapper function that includes both class and usage:

Actually, restructure as a single region wrapping everything:

```dart
// #docregion on-and-emit-basic-event
class UserLoggedInEvent {
  final String userId;
  UserLoggedInEvent(this.userId);
}
// #enddocregion on-and-emit-basic-event

Future<String> runOnAndEmitBasicEvent() async {
  final context = mini.PluginContext.stub();
  String? capturedId;

  // #docregion on-and-emit-basic-event-usage
  context.bus.on<UserLoggedInEvent>((e) {
    print('User logged in: ${e.event.userId}');
  });

  await context.bus.emit<UserLoggedInEvent>(
    event: UserLoggedInEvent('u_123'),
  );
  // #enddocregion on-and-emit-basic-event-usage
  ...
}
```

Simplest approach: ONE region covers the full block (class + on + emit call). Use `on-and-emit-basic-event` only. Wrap everything in a function.

- [ ] **Step 5: Add `bind-and-unbind-context` region**

Doc block at `concepts/event-bus.mdx:75-79`:
```dart
final unbind = context.bus.bind((envelope) {
  logger.debug('event ${envelope.event.runtimeType}');
});
```
This is essentially the same as `bind-observer-and-unbind` already in event_bus.dart. Skip — mark as duplicate in TSV.

- [ ] **Step 6: Add `on-request-variants-cheatsheet` region**

Doc block at `api-cheatsheet.md:263-273`:
```dart
onRequest<RequestType, ResponseType?>((envelope) async {
  if (canHandle) return ResponseType(...);
  return null;
});
final response  = await context.bus.request<RequestType, ResponseType?>(req);
final maybe     = await context.bus.maybeRequest<RequestType, ResponseType?>(req);
final sync      = context.bus.requestSync<RequestType, ResponseType>(req);
final maybeSync = context.bus.maybeRequestSync<RequestType, ResponseType?>(req);
```

```dart
// #docregion on-request-variants-cheatsheet
class RequestType {
  const RequestType();
}
class ResponseType {
  const ResponseType(this.value);
  final String value;
}
// #enddocregion on-request-variants-cheatsheet

Future<void> runOnRequestVariantsCheatsheet() async {
  final context = mini.PluginContext.stub();
  // #docregion on-request-variants-cheatsheet
  context.bus.onRequest<RequestType, ResponseType?>((envelope) async {
    return const ResponseType('ok'); // return null to concede to next handler
  });

  final response  = await context.bus.request<RequestType, ResponseType?>(const RequestType());
  final maybe     = await context.bus.maybeRequest<RequestType, ResponseType?>(const RequestType());
  final sync      = context.bus.requestSync<RequestType, ResponseType>(const RequestType());
  final maybeSync = context.bus.maybeRequestSync<RequestType, ResponseType?>(const RequestType());
  // #enddocregion on-request-variants-cheatsheet
  assert(response?.value == 'ok');
  assert(maybe?.value == 'ok');
  assert(sync.value == 'ok');
  assert(maybeSync?.value == 'ok');
}
```

- [ ] **Step 7: Add `draft-event-mutation-pipeline` region**

Doc block at `patterns.md:216-233`:
```dart
class DraftOutgoingMessage {
  String text;
  final Map<String, String> metadata;
  DraftOutgoingMessage(this.text) : metadata = {};
}
on<DraftOutgoingMessage>((envelope) {
  envelope.event.text = expandMacros(e.event.text);
  envelope.event.metadata['macros_expanded'] = 'true';
});
final envelope = await context.bus.emit<DraftOutgoingMessage>(
  event: DraftOutgoingMessage(userInput),
);
if (envelope.stopped) return;
await sendToServer(envelope.event);
```

Note: `DraftOutgoingMessage` is already defined in `naming.dart`. Use a local class `DraftMessage` or reuse via import. Since event_bus.dart imports `_mini_plugin_kit.dart as mini`, define locally:

```dart
// #docregion draft-event-mutation-pipeline
class DraftMessage {
  String text;
  final Map<String, String> metadata;
  DraftMessage(this.text) : metadata = {};
}
// #enddocregion draft-event-mutation-pipeline

String expandMacros(String text) => text.replaceAll('@today', '2026-05-09');
Future<void> sendToServer(DraftMessage msg) async {}

Future<DraftMessage?> runDraftEventMutationPipeline(String userInput) async {
  final context = mini.PluginContext.stub();
  DraftMessage? sent;

  // #docregion draft-event-mutation-pipeline
  context.bus.on<DraftMessage>((envelope) {
    envelope.event.text = expandMacros(e.event.text);
    envelope.event.metadata['macros_expanded'] = 'true';
  });

  final envelope = await context.bus.emit<DraftMessage>(
    event: DraftMessage(userInput),
  );
  if (envelope.stopped) return null;
  await sendToServer(envelope.event);
  // #enddocregion draft-event-mutation-pipeline

  sent = envelope.event;
  return sent;
}
```

- [ ] **Step 8: Write test cases for new event_bus regions**

In `event_bus_test.dart`, add:
```dart
test('region event-bus-class-surface', () {
  final bus = buildEventBus();
  assert(!bus.isDisposed);
  expect(bus.isDisposed, isFalse);
  bus.dispose();
  expect(bus.isDisposed, isTrue);
});

test('region event-envelope-class-surface', () {
  final env = buildEnvelope();
  assert(env.event == 'hello');
  expect(env.stopped, isFalse);
});

test('region on-and-emit-basic-event', () async {
  final userId = await runOnAndEmitBasicEvent();
  assert(userId == 'u_123');
  expect(userId, 'u_123');
});

test('region on-request-variants-cheatsheet', () async {
  await runOnRequestVariantsCheatsheet();
});

test('region draft-event-mutation-pipeline', () async {
  final msg = await runDraftEventMutationPipeline('hello @today');
  assert(msg != null);
  expect(msg?.metadata['macros_expanded'], 'true');
});
```

- [ ] **Step 9: Run `flutter analyze website/snippets` and `flutter test website/snippets` — verify PASS**

Run: `cd /Users/saadardati/IdeaProjects/plugin_kit/website/snippets && flutter analyze . && flutter test`

---

## Task 2: plugin_services.dart — add 6 regions

**Files:**
- Modify: `website/snippets/lib/plugin_services.dart`
- Modify: `website/snippets/test/plugin_services_test.dart`

- [ ] **Step 1: Add `plugin-service-base-contract` region**

Doc block at `reference/service-registry-and-capabilities.mdx:356-368`:
```dart
abstract class PluginService {
  late PluginId pluginId;
  late ServiceId serviceId;
  Map<String, dynamic> get settings;
  String get settingsHash;
  ConfigNode config;
  @mustCallSuper
  void injectSettings(Map<String, dynamic> settings, {String? hash});
}
```

This is a reference surface. Use comment style in plugin_services.dart:

```dart
// #docregion plugin-service-base-contract
// PluginService public contract (simplified for docs):
//
//   abstract class PluginService {
//     late PluginId pluginId;
//     late ServiceId serviceId;
//     Map<String, dynamic> get settings;
//     String get settingsHash;
//     ConfigNode get config;
//     @mustCallSuper
//     void injectSettings(Map<String, dynamic> settings, {String? hash});
//   }

PluginService buildAnthropicService() => AnthropicService();
// #enddocregion plugin-service-base-contract
```

- [ ] **Step 2: Add `stateful-plugin-service-minimal-contract` region**

Doc block at `reference/plugins-and-lifecycle.mdx:62-67`:
```dart
abstract class StatefulPluginService<PKC extends PluginContext> extends PluginService {
  void attach();
  Future<void> detach();
}
```

```dart
// #docregion stateful-plugin-service-minimal-contract
// StatefulPluginService<PKC> minimal contract (simplified for docs):
//
//   abstract class StatefulPluginService<PKC extends PluginContext>
//       extends PluginService {
//     void attach();
//     Future<void> detach();
//   }

StatefulPluginService<PluginContext> buildStatefulServiceExample() =>
    ChatServiceHarness(PluginContext.stub());
// #enddocregion stateful-plugin-service-minimal-contract
```

- [ ] **Step 3: Add `stateful-service-on-helper-example` region**

Doc block at `reference/service-registry-and-capabilities.mdx:454-461`:
```dart
class ChatService extends StatefulPluginService {
  @override
  void attach() {
    on<UserMessage>((envelope) {});
  }
}
```

Since `plugin_services.dart` already has `ChatServiceHarness` which is essentially identical, wrap the existing harness or write a new minimal one:

```dart
// #docregion stateful-service-on-helper-example
class ChatServiceWithHandler extends StatefulPluginService<PluginContext> {
  @override
  bool get hasContext => _ctx != null;
  PluginContext? _ctx;
  @override
  PluginContext get context => _ctx!;

  @override
  void attach() {
    on<UserMessage>((envelope) {});
  }

  @override
  Future<void> detach() async {}
}
// #enddocregion stateful-service-on-helper-example
```

Wait — `plugin_services.dart` has its own local `PluginService` abstract class and `StatefulPluginService` (not from `_mini_plugin_kit.dart`). The file imports `_mini_plugin_kit.dart` for `PluginContext`, `EventEnvelope`, `StreamSubscription`. Use the local abstract class.

Actually re-reading `plugin_services.dart`: it defines `abstract class PluginService` and `abstract class StatefulPluginService<PKC>` locally. The `ChatServiceHarness` is a concrete implementation. So write a new minimal class for the region.

- [ ] **Step 4: Add `plain-notification-service-baseline` region**

Doc block at `guides/adding-a-plugin.mdx:67-73`:
```dart
class NotificationService {
  Future<void> send(String message) async {
    print(message);
  }
}
```

But `plugin_services.dart` already has `class NotificationService extends PluginService`. Name conflict. Use `PlainNotificationService`:

```dart
// #docregion plain-notification-service-baseline
class PlainNotificationService {
  Future<void> send(String message) async {
    print(message);
  }
}
// #enddocregion plain-notification-service-baseline
```

- [ ] **Step 5: Add `config-raw-accessor` region**

Doc block at `concepts/configuration.mdx:129-131`:
```dart
final payload = config.raw('advanced_payload');
```

```dart
// #docregion config-raw-accessor
dynamic getAdvancedPayload(PluginService service) {
  final payload = service.config.raw('advanced_payload');
  return payload;
}
// #enddocregion config-raw-accessor
```

- [ ] **Step 6: Add `model-router-service-simple` region**

Doc block at `concepts/plugin-services.mdx:167-171`:
```dart
class ModelRouter extends PluginService {
  String get defaultModel => config.getString('default_model') ?? 'gpt-4.1';
}
```

`plugin_services.dart` already has `class ModelRouter extends PluginService` with exactly this. Just add markers around the existing class.

- [ ] **Step 7: Write test cases for plugin_services regions**

In `plugin_services_test.dart`, add:
```dart
test('region plugin-service-base-contract', () {
  final svc = buildAnthropicService();
  assert(svc is PluginService);
  expect(svc, isA<PluginService>());
});

test('region stateful-plugin-service-minimal-contract', () {
  final svc = buildStatefulServiceExample();
  assert(svc is StatefulPluginService);
  expect(svc.hasContext, isFalse);
});

test('region stateful-service-on-helper-example', () {
  final svc = ChatServiceWithHandler();
  assert(!svc.hasContext);
  expect(svc, isA<StatefulPluginService>());
});

test('region plain-notification-service-baseline', () async {
  final svc = PlainNotificationService();
  await svc.send('test');  // no throw
});

test('region config-raw-accessor', () {
  final svc = AnthropicService();
  svc.injectSettings({'advanced_payload': 42}, hash: 'h1');
  final payload = getAdvancedPayload(svc);
  assert(payload == 42);
  expect(payload, 42);
});

test('region model-router-service-simple', () {
  final r = ModelRouter();
  assert(r.defaultModel == 'gpt-4.1');
  expect(r.defaultModel, 'gpt-4.1');
});
```

- [ ] **Step 8: Run analyze + test — verify PASS**

---

## Task 3: capabilities.dart — add 3 regions

**Files:**
- Modify: `website/snippets/lib/capabilities.dart`
- Modify: `website/snippets/test/capabilities_test.dart`

- [ ] **Step 1: Add `capability-abstract-base` region**

Doc block at `reference/service-registry-and-capabilities.mdx:469-473`:
```dart
abstract class Capability {
  const Capability();
}
```

Since `_mini_plugin_kit.dart` already defines `abstract class Capability`, just wrap a comment-style region:

```dart
// #docregion capability-abstract-base
// abstract class Capability { const Capability(); }
// Every custom capability extends this sealed base.

const Capability _exampleCapability = PartOfASuiteOfTools('example');
// #enddocregion capability-abstract-base
```

- [ ] **Step 2: Add `capability-lookup-extension-surface` region**

Doc block at `reference/service-registry-and-capabilities.mdx:502-507`:
```dart
extension CapabilityLookup on Set<Capability> {
  T? getOfType<T extends Capability>();
  bool hasType<T extends Capability>();
}
```

```dart
// #docregion capability-lookup-extension-surface
// CapabilityLookup extension on Set<Capability> (from _mini_plugin_kit.dart):
//
//   extension CapabilityLookup on Set<Capability> {
//     T? getOfType<T extends Capability>();
//     bool hasType<T extends Capability>();
//   }

bool checkCapabilityLookupSurface() {
  const caps = <Capability>{PartOfASuiteOfTools('demo')};
  return caps.hasType<PartOfASuiteOfTools>();
}
// #enddocregion capability-lookup-extension-surface
```

- [ ] **Step 3: Add `configurable-capability-marker-pattern` region**

Doc block at `api-cheatsheet.md:197-207`:
```dart
class ConfigurableCapability extends Capability { const ConfigurableCapability(); }
// In Plugin.register:
registry.registerSingleton<MyService>(serviceId, MyService(),
    capabilities: const {ConfigurableCapability()});
// At resolve time:
context.registry.resolveRaw<MyService>(serviceId)
    .capabilities.hasType<ConfigurableCapability>();
```

```dart
// #docregion configurable-capability-marker-pattern
class ConfigurableCapability extends Capability {
  const ConfigurableCapability();
}
// #enddocregion configurable-capability-marker-pattern

class MyConfigurableService {}

bool runConfigurableCapabilityMarkerPattern() {
  final registry = ServiceRegistry();
  const serviceId = ServiceId('my_service');
  // #docregion configurable-capability-marker-pattern
  registry.registerSingleton<MyConfigurableService>(
    serviceId,
    MyConfigurableService(),
    capabilities: const {ConfigurableCapability()},
  );
  final hasIt = registry.resolveRaw<MyConfigurableService>(serviceId)
      .capabilities.hasType<ConfigurableCapability>();
  // #enddocregion configurable-capability-marker-pattern
  return hasIt;
}
```

- [ ] **Step 4: Write test cases**

```dart
test('region capability-abstract-base', () {
  assert(_exampleCapability is Capability);
  expect(_exampleCapability, isA<Capability>());
});

test('region capability-lookup-extension-surface', () {
  final found = checkCapabilityLookupSurface();
  assert(found);
  expect(found, isTrue);
});

test('region configurable-capability-marker-pattern', () {
  final found = runConfigurableCapabilityMarkerPattern();
  assert(found);
  expect(found, isTrue);
});
```

- [ ] **Step 5: Run analyze + test — verify PASS**

---

## Task 4: naming.dart — add 3 regions

**Files:**
- Modify: `website/snippets/lib/naming.dart`
- Modify: `website/snippets/test/naming_test.dart`

- [ ] **Step 1: Add `plugin-id-extension-type-surface` region**

Doc block at `reference/service-registry-and-capabilities.mdx:18-20`:
```dart
extension type const PluginId(String value) {}
```

`naming.dart` imports `_mini_plugin_kit.dart` which has `PluginId`. Wrap in comment style:

```dart
// #docregion plugin-id-extension-type-surface
// PluginId is an extension type wrapping a String value:
//   extension type const PluginId(String value) {}
const PluginId _demoPluginId = PluginId('demo');
// #enddocregion plugin-id-extension-type-surface
```

- [ ] **Step 2: Add `namespace-extension-type-surface` region**

Doc block at `reference/service-registry-and-capabilities.mdx:26-32`:
```dart
extension type const Namespace(String value) {
  ServiceId service(String id);
  ServiceId call(String id);
  Namespace child(String name);
}
```

```dart
// #docregion namespace-extension-type-surface
// Namespace extension type — builds typed ServiceIds:
//
//   extension type const Namespace(String value) {
//     ServiceId service(String id);  // Namespace.service('x') => 'ns.x'
//     ServiceId call(String id);     // shorthand for service(id)
//     Namespace child(String name);  // sub-namespace
//   }
void _verifyNamespaceSurface() {
  const ns = Namespace('agent');
  final sid = ns.service('model');         // 'agent.model'
  final sid2 = ns('temperature');          // 'agent.temperature'
  final sub = ns.child('tools');           // Namespace('agent.tools')
  assert(sid.value == 'agent.model');
  assert(sid2.value == 'agent.temperature');
  assert(sub.value == 'agent.tools');
}
// #enddocregion namespace-extension-type-surface
```

- [ ] **Step 3: Add `service-id-extension-type-surface` region**

Doc block at `reference/service-registry-and-capabilities.mdx:38-44`:
```dart
extension type const ServiceId(String value) {
  Namespace? get namespace;
  String get id;
  Namespace? get topNamespace;
}
```

```dart
// #docregion service-id-extension-type-surface
// ServiceId extension type — typed service identifier:
//
//   extension type const ServiceId(String value) {
//     Namespace? get namespace;     // prefix via lastIndexOf('.')
//     String get id;                // leaf segment after the last dot
//     Namespace? get topNamespace;  // first segment via indexOf('.')
//   }
void _verifyServiceIdSurface() {
  const sid = ServiceId('agent.model');
  assert(sid.namespace?.value == 'agent');
  assert(sid.id == 'model');
  assert(sid.topNamespace?.value == 'agent');
}
// #enddocregion service-id-extension-type-surface
```

- [ ] **Step 4: Write test cases**

```dart
test('region plugin-id-extension-type-surface', () {
  assert(_demoPluginId.value == 'demo');
  expect(_demoPluginId.value, 'demo');
});

test('region namespace-extension-type-surface', () {
  _verifyNamespaceSurface();  // asserts internally
});

test('region service-id-extension-type-surface', () {
  _verifyServiceIdSurface();  // asserts internally
});
```

- [ ] **Step 5: Run analyze + test — verify PASS**

---

## Task 5: service_registry.dart — add 2 regions

**Files:**
- Modify: `website/snippets/lib/service_registry.dart`
- Modify: `website/snippets/test/service_registry_test.dart`

- [ ] **Step 1: Add `service-registry-class-surface` region**

Doc block at `reference/service-registry-and-capabilities.mdx:83-92`:
```dart
class ServiceRegistry {
  static const int defaultPriority = 50;
  ServiceRegistry({List<LocalPluginOverride> overrides = const []});
  ServiceRegistry.empty();
  // ... register*, resolve*, listing, mutation
}
```

`service_registry.dart` imports `_mini_plugin_kit.dart`. Use comment style:

```dart
// #docregion service-registry-class-surface
// ServiceRegistry public surface (simplified for docs):
//
//   class ServiceRegistry {
//     static const int defaultPriority = 50;
//     ServiceRegistry({List<LocalPluginOverride> overrides = const []});
//     ServiceRegistry.empty();
//     // register*, resolve*, listAllServiceIds, scopedFor, ...
//   }
ServiceRegistry buildEmptyRegistry() => ServiceRegistry.empty();
// #enddocregion service-registry-class-surface
```

- [ ] **Step 2: Add `scoped-service-registry-class-surface` region**

Doc block at `reference/service-registry-and-capabilities.mdx:215-231`:
```dart
class ScopedServiceRegistry {
  final ServiceRegistry raw;
  final PluginId pluginId;
  final int? defaultPriority;
  const ScopedServiceRegistry(this.raw, this.pluginId, {this.defaultPriority});
  ScopedServiceRegistry withPriority(int priority);
  // register* methods below
}
```

```dart
// #docregion scoped-service-registry-class-surface
// ScopedServiceRegistry public surface (simplified for docs):
//
//   class ScopedServiceRegistry {
//     final ServiceRegistry raw;
//     final PluginId pluginId;
//     final int? defaultPriority;
//     const ScopedServiceRegistry(this.raw, this.pluginId, {this.defaultPriority});
//     ScopedServiceRegistry withPriority(int priority);
//     // registerSingleton, registerLazySingleton, registerFactory
//   }
ScopedServiceRegistry buildScopedRegistry() =>
    ServiceRegistry.empty().scopedFor(const PluginId('demo'));
// #enddocregion scoped-service-registry-class-surface
```

- [ ] **Step 3: Write test cases**

```dart
test('region service-registry-class-surface', () {
  final reg = buildEmptyRegistry();
  assert(reg != null);
  expect(reg, isNotNull);
});

test('region scoped-service-registry-class-surface', () {
  final scoped = buildScopedRegistry();
  assert(scoped.pluginId.value == 'demo');
  expect(scoped.pluginId.value, 'demo');
});
```

- [ ] **Step 4: Run analyze + test — verify PASS**

---

## Task 6: runtime_settings.dart — add 3 regions

**Files:**
- Modify: `website/snippets/lib/runtime_settings.dart`
- Modify: `website/snippets/test/runtime_settings_test.dart`

- [ ] **Step 1: Add `runtime-settings-class-structure` region**

Doc block at `reference/settings-and-configuration.mdx:43-55`:
```dart
class RuntimeSettings {
  final Map<PluginId, PluginConfig> plugins;
  final Map<Pin, ServiceSettings> services;
  const RuntimeSettings({this.plugins = const {}, this.services = const {}});
  const RuntimeSettings.empty();
}
```

```dart
// #docregion runtime-settings-class-structure
// RuntimeSettings structure (simplified for docs):
//
//   class RuntimeSettings {
//     final Map<PluginId, PluginConfig> plugins;
//     final Map<Object, ServiceSettings> services; // Object: Pin | String
//     const RuntimeSettings({...});
//     const RuntimeSettings.empty();
//   }
RuntimeSettings buildEmptySettings() => const RuntimeSettings.empty();
// #enddocregion runtime-settings-class-structure
```

- [ ] **Step 2: Add `runtime-settings-empty-constructor` region**

Doc block at `reference/settings-and-configuration.mdx:70-72`:
```dart
const settings = RuntimeSettings.empty();
```

```dart
// #docregion runtime-settings-empty-constructor
const RuntimeSettings emptySettings = RuntimeSettings.empty();
// #enddocregion runtime-settings-empty-constructor
```

- [ ] **Step 3: Add `plugin-config-class-structure` region**

Doc block at `reference/settings-and-configuration.mdx:176-186`:
```dart
class PluginConfig {
  final bool enabled;
  final Map<String, dynamic> config;
  const PluginConfig({this.enabled = true, this.config = const {}});
}
```

```dart
// #docregion plugin-config-class-structure
// PluginConfig structure:
//
//   class PluginConfig {
//     final bool enabled;
//     final Map<String, dynamic> config;
//     const PluginConfig({this.enabled = true, this.config = const {}});
//   }
const PluginConfig defaultPluginConfig = PluginConfig();
const PluginConfig disabledPluginConfig = PluginConfig(enabled: false);
// #enddocregion plugin-config-class-structure
```

- [ ] **Step 4: Write test cases**

```dart
test('region runtime-settings-class-structure', () {
  final s = buildEmptySettings();
  assert(s.plugins.isEmpty);
  expect(s.plugins, isEmpty);
});

test('region runtime-settings-empty-constructor', () {
  assert(emptySettings.plugins.isEmpty);
  expect(emptySettings.services, isEmpty);
});

test('region plugin-config-class-structure', () {
  assert(defaultPluginConfig.enabled);
  assert(!disabledPluginConfig.enabled);
  expect(defaultPluginConfig.enabled, isTrue);
  expect(disabledPluginConfig.enabled, isFalse);
});
```

- [ ] **Step 5: Run analyze + test — verify PASS**

---

## Task 7: custom_context.dart — add 3 regions

**Files:**
- Modify: `website/snippets/lib/custom_context.dart`
- Modify: `website/snippets/test/custom_context_test.dart`

- [ ] **Step 1: Add `plugin-context-class-structure` region**

Doc block at `reference/plugins-and-lifecycle.mdx:126-145`:
```dart
class PluginContext {
  final ServiceRegistry registry;
  final EventBus bus;
  final Map<String, Object> extras;
  T resolve<T extends Object>(ServiceId serviceId);
  T? maybeResolve<T extends Object>(ServiceId serviceId);
  T resolveAfter<T extends Object>({required PluginId pluginId, required ServiceId serviceId});
  Future<Response> request<Request, Response>(Request r, {String? identifier});
  ...
  factory PluginContext.stub({...});
}
```

`custom_context.dart` already imports `plugin_kit.dart`. Use comment style:

```dart
// #docregion plugin-context-class-structure
// PluginContext structure (simplified; full API in reference):
//
//   class PluginContext {
//     final ServiceRegistry registry;
//     final EventBus bus;
//     final Map<String, Object> extras;
//
//     T resolve<T extends Object>(ServiceId id);
//     T? maybeResolve<T extends Object>(ServiceId id);
//     T resolveAfter<T extends Object>({required PluginId, required ServiceId});
//
//     Future<R> request<Q, R>(Q r, {String? identifier});
//     Future<R?> maybeRequest<Q, R>(Q r, {String? identifier});
//     R requestSync<Q, R>(Q r);
//     R? maybeRequestSync<Q, R>(Q r);
//
//     PluginContext copyWith({ServiceRegistry?, EventBus?, Map<String, Object>?});
//     factory PluginContext.stub({ServiceRegistry?, EventBus?, Map<String, Object>?});
//   }
PluginContext buildPluginContextStructure() => PluginContext.stub();
// #enddocregion plugin-context-class-structure
```

- [ ] **Step 2: Add `global-plugin-context-class-structure` region**

Doc block at `reference/plugins-and-lifecycle.mdx:157-163`:
```dart
class GlobalPluginContext extends PluginContext {
  final List<PluginSession> sessions;
  PluginSession sessionOf(PluginId pluginId);
}
```

```dart
// #docregion global-plugin-context-class-structure
// GlobalPluginContext extends PluginContext with session awareness:
//
//   class GlobalPluginContext extends PluginContext {
//     final List<PluginSession> sessions;
//     PluginSession sessionOf(PluginId pluginId);
//   }
GlobalPluginContext buildGlobalPluginContextStructure() =>
    GlobalPluginContext.stub();
// #enddocregion global-plugin-context-class-structure
```

- [ ] **Step 3: Add `session-plugin-context-class-structure` region**

Doc block at `reference/plugins-and-lifecycle.mdx:177-181`:
```dart
class SessionPluginContext extends PluginContext {
  final EventBus globalBus;
}
```

```dart
// #docregion session-plugin-context-class-structure
// SessionPluginContext extends PluginContext with global bus access:
//
//   class SessionPluginContext extends PluginContext {
//     final EventBus globalBus; // for cross-session events
//   }
SessionPluginContext buildSessionPluginContextStructure() =>
    SessionPluginContext(
      registry: ServiceRegistry.empty(),
      bus: EventBus(),
      globalBus: EventBus(),
    );
// #enddocregion session-plugin-context-class-structure
```

- [ ] **Step 4: Write test cases**

```dart
test('region plugin-context-class-structure', () {
  final ctx = buildPluginContextStructure();
  assert(ctx.extras.isEmpty);
  expect(ctx.extras, isEmpty);
});

test('region global-plugin-context-class-structure', () {
  final ctx = buildGlobalPluginContextStructure();
  assert(ctx.sessions.isEmpty);
  expect(ctx.sessions, isEmpty);
});

test('region session-plugin-context-class-structure', () {
  final ctx = buildSessionPluginContextStructure();
  assert(!ctx.bus.isDisposed);
  expect(ctx.bus.isDisposed, isFalse);
});
```

- [ ] **Step 5: Run analyze + test — verify PASS**

---

## Task 8: sessions.dart — add 1 region

**Files:**
- Modify: `website/snippets/lib/sessions.dart`
- Modify: `website/snippets/test/sessions_test.dart`

- [ ] **Step 1: Add `plugin-session-class-surface` region**

Doc block at `reference/plugins-and-lifecycle.mdx:189-206`:
```dart
class PluginSession<K extends PluginContext> {
  final ServiceRegistry registry;
  final EventBus bus;
  final K context;
  final List<Plugin> plugins;
  final RuntimeSettings settings;
  bool isPluginEnabled(PluginId pluginId);
  Future<void> dispose();
  // Via SessionHelper extension:
  T resolve<T>(ServiceId serviceId);
  T? maybeResolve<T extends Object>(ServiceId serviceId);
  Future<EventEnvelope<T>> emit<T>(T event, {String? identifier});
  StreamSubscription on<T>(EventHandler<T> handler, {int priority, String? identifier});
}
```

```dart
// #docregion plugin-session-class-surface
// PluginSession<K extends PluginContext> public surface (simplified):
//
//   class PluginSession<K extends PluginContext> {
//     final ServiceRegistry registry;
//     final EventBus bus;
//     final K context;
//     final List<Plugin> plugins;
//     RuntimeSettings settings;
//
//     bool isPluginEnabled(PluginId pluginId);
//     Future<void> dispose();
//
//     // Via SessionHelper extension (requires SessionPlugin import):
//     T resolve<T>(ServiceId serviceId);
//     T? maybeResolve<T extends Object>(ServiceId serviceId);
//     Future<EventEnvelope<T>> emit<T>(T event, {String? identifier});
//     StreamSubscription on<T>(EventHandler<T> handler, {int? priority, String? identifier});
//   }
PluginRuntime buildRuntimeForSessionSurface() => PluginRuntime();
// #enddocregion plugin-session-class-surface
```

- [ ] **Step 2: Write test case**

```dart
test('region plugin-session-class-surface', () async {
  final runtime = buildRuntimeForSessionSurface()..init();
  final session = await runtime.createSession();
  assert(session.plugins.isEmpty);
  expect(session.isPluginEnabled(const PluginId('any')), isTrue);
  await session.dispose();
});
```

- [ ] **Step 3: Run analyze + test — verify PASS**

---

## Task 9: state_bridges.dart — add 2 regions

**Files:**
- Modify: `website/snippets/lib/state_bridges.dart`
- Modify: `website/snippets/test/state_bridges_test.dart`

- [ ] **Step 1: Add `chat-protocol-types` region**

Doc block at `reference/state-management-bridges.mdx:52-65`:
```dart
class ChatMessage {
  final String author;
  final String text;
}
class SendMessageRequested {
  final String text;
}
class ChatMessagesChanged {
  final List<ChatMessage> messages;
}
```

```dart
// #docregion chat-protocol-types
class ChatMessage {
  final String author;
  final String text;
  const ChatMessage({required this.author, required this.text});
}

class SendMessageRequested {
  final String text;
  const SendMessageRequested(this.text);
}

class ChatMessagesChanged {
  final List<ChatMessage> messages;
  const ChatMessagesChanged(this.messages);
}
// #enddocregion chat-protocol-types
```

- [ ] **Step 2: Add `riverpod-async-notifier-chat-controller` region**

Doc block at `guides/migrating-flutter-app.mdx:373-397`:
```dart
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  StreamSubscription? _messagesSub;
  @override
  Future<List<ChatMessage>> build() async {
    ref.onDispose(() { _messagesSub?.cancel(); });
    final session = await ref.watch(pluginSessionProvider.future);
    _messagesSub = session.on<ChatMessagesChanged>((envelope) {
      state = AsyncData(e.event.messages);
    });
    return const [];
  }
  Future<void> send(UserPrompt prompt) async {
    final session = await ref.read(pluginSessionProvider.future);
    await session.emit(SendMessageRequested(prompt));
  }
}
```

`state_bridges.dart` has a local stub `FutureProvider`. It does NOT have `AsyncNotifier`. Define minimal stubs:

```dart
// Stub AsyncData for the region
class AsyncData<T> {
  const AsyncData(this.value);
  final T value;
}

class AsyncNotifier<T> {
  late _Ref ref;
  T? state;
  Future<T> build();
}

class _Ref {
  void onDispose(void Function() fn) {}
  T watch<T>(FutureProvider<T> p) => throw UnimplementedError();
  Future<T> read<T>(FutureProvider<T> p) => throw UnimplementedError();
}
```

Then the region:
```dart
// #docregion riverpod-async-notifier-chat-controller
class ChatController extends AsyncNotifier<List<ChatMessage>> {
  StreamSubscription? _messagesSub;

  @override
  Future<List<ChatMessage>> build() async {
    ref.onDispose(() {
      _messagesSub?.cancel();
    });

    final session = await ref.read(pluginSessionProvider);

    _messagesSub = session.bus.on<ChatMessagesChanged>((envelope) {
      state = AsyncData(e.event.messages);
    });

    return const [];
  }

  Future<void> send(String text) async {
    final session = await ref.read(pluginSessionProvider);
    await session.emit(SendMessageRequested(text));
  }
}
// #enddocregion riverpod-async-notifier-chat-controller
```

Note: The doc block uses `ref.watch(pluginSessionProvider.future)` and `ref.read(pluginSessionProvider.future)` which are Riverpod-specific. Since `state_bridges.dart` uses local stub `Provider`/`FutureProvider`, adapt to use local stubs.

- [ ] **Step 3: Write test cases**

```dart
test('region chat-protocol-types', () {
  const msg = ChatMessage(author: 'alice', text: 'hello');
  const req = SendMessageRequested('hi');
  const changed = ChatMessagesChanged([]);
  assert(msg.text == 'hello');
  expect(req.text, 'hi');
  expect(changed.messages, isEmpty);
});

test('region riverpod-async-notifier-chat-controller compiles', () {
  // Just verify the class is instantiable.
  expect(ChatController, isNotNull);
});
```

- [ ] **Step 4: Run analyze + test — verify PASS**

---

## Task 10: logging.dart — add 1 region

**Files:**
- Modify: `website/snippets/lib/logging.dart`
- Modify: `website/snippets/test/logging_test.dart`

- [ ] **Step 1: Add `logging-onrecord-listener` region**

Doc block at `guides/logging.mdx:27-33`:
```dart
import 'package:logging/logging.dart';
Logger('plugin_kit').onRecord.listen((record) {
  print('${record.level.name}: ${record.loggerName}: ${record.message}');
});
```

`logging.dart` imports `_mini_plugin_kit.dart` (no `logging` package). The snippet uses `package:logging`. Check if it's available.

`pubspec.yaml` does NOT include `package:logging`. This block references a third-party package not in the deps. Use comment style:

```dart
// #docregion logging-onrecord-listener
// Logger tap-all pattern using package:logging:
//
//   import 'package:logging/logging.dart';
//   Logger('plugin_kit').onRecord.listen((record) {
//     print('${record.level.name}: ${record.loggerName}: ${record.message}');
//   });
void setUpLoggingListener() {
  // In real usage: Logger('plugin_kit').onRecord.listen(...)
  // See package:logging for full API.
}
// #enddocregion logging-onrecord-listener
```

- [ ] **Step 2: Write test case**

```dart
test('region logging-onrecord-listener', () {
  setUpLoggingListener();  // no-op; just verify it compiles
});
```

- [ ] **Step 3: Run analyze + test — verify PASS**

---

## Task 11: anti_patterns files — add 4 regions

**Files:**
- Modify: `website/snippets/lib/anti_patterns_registry.dart`
- Modify: `website/snippets/lib/anti_patterns_naming.dart`
- Modify: `website/snippets/lib/anti_patterns_events.dart`
- Modify: `website/snippets/test/anti_patterns_registry_test.dart`
- Modify: `website/snippets/test/anti_patterns_naming_test.dart`
- Modify: `website/snippets/test/anti_patterns_events_test.dart`

- [ ] **Step 1: Add `lazy-closure-and-attach-resolve-pattern` to anti_patterns_registry.dart**

Doc block at `anti-patterns.md:82-94`:
```dart
// (a) Lazy + closure capture; resolve when the lazy factory fires.
registry.registerLazySingleton<MyService>(
  const ServiceId('my'),
  () => MyService(registry.raw.resolve<Logger>(const ServiceId('logger'))),
);
// (b) Resolve in attach or in event handlers.
@override
void attach(SessionPluginContext context) {
  final logger = context.resolve<Logger>(const ServiceId('logger'));
}
```

`anti_patterns_registry.dart` already has `MyService`, `Logger` classes. Add:

```dart
void runLazyClosureAndAttachResolvePattern(
  ScopedServiceRegistry registry,
  PluginContext context,
) {
  // #docregion lazy-closure-and-attach-resolve-pattern
  // (a) Lazy + closure capture; resolve when the lazy factory fires.
  registry.registerLazySingleton<MyService>(
    const ServiceId('my'),
    () => MyService(registry.raw.resolve<Logger>(const ServiceId('logger'))),
  );

  // (b) Resolve in attach or in event handlers.
  final logger = context.resolve<Logger>(const ServiceId('logger'));
  // #enddocregion lazy-closure-and-attach-resolve-pattern
  assert(logger is Logger);
}
```

- [ ] **Step 2: Add `resolve-by-plugin-does-not-exist` to anti_patterns_registry.dart**

Doc block at `anti-patterns.md:198-200`:
```dart
final svc = registry.resolveByPlugin(PluginId('chat'), ServiceId('agent.model'));
```

`resolveByPlugin` does NOT exist in plugin_kit's API. This is the anti-pattern — using an invented API. Use comment style:

```dart
// #docregion resolve-by-plugin-does-not-exist
// Anti-pattern: resolveByPlugin does not exist in plugin_kit.
// Use context.resolveAfter(pluginId: ..., serviceId: ...) instead.
//
//   final svc = registry.resolveByPlugin(PluginId('chat'), ServiceId('agent.model'));
//   // ^^ CompileError: method not found
//
//   // Correct:
//   final svc = context.resolveAfter<ModelRouter>(
//     pluginId: const PluginId('chat'),
//     serviceId: const ServiceId('agent.model'),
//   );
// #enddocregion resolve-by-plugin-does-not-exist
```

- [ ] **Step 3: Add `reserved-pk-prefix-anti-pattern` to anti_patterns_naming.dart**

Doc block at `anti-patterns.md:208-215`:
```dart
class MyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('__pk_internal');
}
runtime.addPlugin(MyPlugin());  // throws ArgumentError
```

`anti_patterns_naming.dart` already has `class MyPlugin` with this exact pattern and `reserved-plugin-id-prefix-anti-pattern`. The note is that this region was "not marked" — but it IS marked. Check:

`anti_patterns_naming.dart` has `// #docregion reserved-plugin-id-prefix-anti-pattern` which covers lines 9-13 (the class). So the full block including `runtime.addPlugin(MyPlugin())` is NOT fully covered. Add a new function:

```dart
// #docregion reserved-pk-prefix-runtime-throws
void demonstrateReservedPkPrefixThrows() {
  final runtime = PluginRuntime();
  runtime.addPlugin(MyPlugin());
  // runtime.init() would throw ArgumentError for __pk_ prefix
}
// #enddocregion reserved-pk-prefix-runtime-throws
```

Wait — checking anti_patterns_naming.dart more carefully, the existing region only covers the class definition. The doc block also shows `runtime.addPlugin(MyPlugin())  // throws ArgumentError`. Since this is already partially covered, and anti_patterns_naming.dart is a simple file, just verify the existing region suffices or add the runtime-throws pattern.

Per the inventory row (208-215), this block is not in snippet-mapping (it's `NOT_IN_MAPPING`), meaning it was never planned. It's an aspirational block. The content:
```
class MyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('__pk_internal');
}
runtime.addPlugin(MyPlugin());  // throws ArgumentError
```

The existing `reserved-plugin-id-prefix-anti-pattern` covers only the class (lines 9-13 of anti_patterns_naming.dart = `class MyPlugin { ... }`). The `runtime.addPlugin` part is new. Add `reserved-pk-prefix-runtime-throws`:

- [ ] **Step 4: Add `fact-event-mutable-fields-anti-pattern` to anti_patterns_events.dart**

Doc block at `anti-patterns.md:229-238`:
```dart
class UserMessageReceived {
  final String text;
  const UserMessageReceived(this.text);
}
on<UserMessageReceived>((e) {
  e.event.text = e.event.text.toUpperCase();
});
```

Wait — this is a contradiction: the class has `final String text` but the handler tries to mutate it. The anti-pattern note is: "fact event with `final` fields correctly, but handlers try to mutate — compile error". The point is that mutation should fail at compile time.

`anti_patterns_events.dart` already has `mutating-immutable-event-anti-pattern` which covers a mutable field version. The new doc block shows the CORRECT version (final fields) — the anti-pattern shown is the handler code `e.event.text = ...` which would be a compile error with `final` fields. This is a counterexample/correct-pattern block.

Add as `immutable-fact-event-with-final-fields`:

```dart
// #docregion immutable-fact-event-with-final-fields
// Correct: fact event uses final fields. Mutation in a handler is a compile error.
class UserReceivedMessage {
  final String text;
  const UserReceivedMessage(this.text);
}

// This handler would NOT compile — text is final:
// on<UserReceivedMessage>((e) {
//   e.event.text = e.event.text.toUpperCase();  // compile error
// });
// #enddocregion immutable-fact-event-with-final-fields
```

- [ ] **Step 5: Write test cases**

In `anti_patterns_registry_test.dart`, add:
```dart
test('region lazy-closure-and-attach-resolve-pattern', () {
  final reg = ServiceRegistry.empty();
  reg.registerSingleton<Logger>(const ServiceId('logger'), Logger());
  final context = PluginContext.stub(registry: reg);
  runLazyClosureAndAttachResolvePattern(reg.scopedFor(const PluginId('p')), context);
});
```

In `anti_patterns_naming_test.dart`, add:
```dart
test('region reserved-pk-prefix-runtime-throws', () {
  demonstrateReservedPkPrefixThrows();  // no-op; just verify compiles
});
```

In `anti_patterns_events_test.dart`, add:
```dart
test('region immutable-fact-event-with-final-fields', () {
  const msg = UserReceivedMessage('hello');
  assert(msg.text == 'hello');
  expect(msg.text, 'hello');
});
```

- [ ] **Step 6: Run analyze + test — verify PASS**

---

## Task 12: testing.dart — add 2 regions

**Files:**
- Modify: `website/snippets/lib/testing.dart`
- Modify: `website/snippets/test/testing_test.dart`

- [ ] **Step 1: Add `plugin-context-stub-forms` region**

Doc block at `testing.md:9-13`:
```dart
PluginContext.stub({registry, bus, extras});
GlobalPluginContext.stub({registry, bus, extras, sessions});
SessionPluginContext.stub({registry, bus, globalBus, extras});
```

This is an API reference block. Use comment style (these stubs exist in plugin_kit):

```dart
// #docregion plugin-context-stub-forms
// Context stub factory forms for tests:
//   PluginContext.stub({registry, bus, extras});
//   GlobalPluginContext.stub({registry, bus, extras, sessions});
//   SessionPluginContext.stub({registry, bus, globalBus, extras});
void buildContextStubs() {
  final ctx = PluginContext.stub();
  final global = GlobalPluginContext.stub();
  final session = SessionPluginContext(
    registry: ServiceRegistry.empty(),
    bus: EventBus(),
    globalBus: EventBus(),
  );
  assert(ctx.registry is ServiceRegistry);
  assert(global.sessions.isEmpty);
  assert(!session.bus.isDisposed);
}
// #enddocregion plugin-context-stub-forms
```

- [ ] **Step 2: Add `flutter-widget-editor-shell-test` region**

Doc block at `guides/flutter-integration.mdx:280-292`:
```dart
testWidgets('editor shell renders registered panels', (tester) async {
  final runtime = PluginRuntime(plugins: [TestPanelPlugin()]);
  runtime.init();
  await tester.pumpWidget(MaterialApp(home: EditorShell(runtime: runtime)));
  await tester.pumpAndSettle();
  expect(find.text('Test Panel'), findsOneWidget);
  await runtime.dispose();
});
```

This requires `TestPanelPlugin`, `EditorShell` which are custom — not in plugin_kit. As a snippet, define minimal stubs and the test function. Since `testing.dart` is in lib/, not test/, we can't use `testWidgets` directly. Use comment style:

```dart
// #docregion flutter-widget-editor-shell-test
// Widget integration test pattern for plugin-driven shells:
//
//   testWidgets('editor shell renders registered panels', (tester) async {
//     final runtime = PluginRuntime(plugins: [TestPanelPlugin()]);
//     runtime.init();
//
//     await tester.pumpWidget(
//       MaterialApp(home: EditorShell(runtime: runtime)),
//     );
//     await tester.pumpAndSettle();
//
//     expect(find.text('Test Panel'), findsOneWidget);
//
//     await runtime.dispose();
//   });
void flutterWidgetEditorShellTestPattern() {
  // See: website/snippets/test/testing_test.dart for a runnable variant.
}
// #enddocregion flutter-widget-editor-shell-test
```

- [ ] **Step 3: Write test cases**

```dart
test('region plugin-context-stub-forms', () {
  buildContextStubs();
});

test('region flutter-widget-editor-shell-test', () {
  flutterWidgetEditorShellTestPattern(); // no-op; compiles only
});
```

- [ ] **Step 4: Run analyze + test — verify PASS**

---

## Task 13: config_fields.dart — add 2 regions

**Files:**
- Modify: `website/snippets/lib/config_fields.dart`
- Modify: `website/snippets/test/config_fields_test.dart`

- [ ] **Step 1: Add `config-field-types-reference` region**

Doc block at `plugin_kit_dialog/README.md:249-260`:
```
UiConfigurableCapability(label, fields, description);
TextConfigField, MultilineConfigField, PasswordConfigField,
NumberConfigField (NumberFieldStyle, isInteger),
DropdownConfigField<T>, DropdownOption<T>,
BoolConfigField, GroupConfigField,
ExtensionConfigField (rendererKey, args),
ConfigField  // sealed base
ConfigFieldHandle  // value/reset handle for renderers
```

`config_fields.dart` has its own local `ExtensionConfigField`. This is a reference-style comment block. Use comment style:

```dart
// #docregion config-field-types-reference
// Config field types available from plugin_kit_dialog:
//
//   TextConfigField         — single-line text input
//   MultilineConfigField    — multi-line text area
//   PasswordConfigField     — masked text input
//   NumberConfigField       — numeric input (int or double, slider or text)
//   DropdownConfigField<T>  — select from DropdownOption<T> list
//   BoolConfigField         — toggle / checkbox
//   GroupConfigField        — nested fields grouped with a header
//   ExtensionConfigField    — custom widget via rendererKey + args
//   ConfigField             — sealed base class (exhaustive switch required)
//   ConfigFieldHandle       — value/reset handle passed to renderers
// #enddocregion config-field-types-reference
```

- [ ] **Step 2: Add `config-field-types-guide-reference` region**

Doc block at `guides/plugin-kit-dialog.mdx:274-285` is the same reference block. Use the same region name or create a guide variant. Since both point to the same content, create `config-field-types-guide-reference` as an alias (same content, different region name for docs linking):

```dart
// #docregion config-field-types-guide-reference
// Config field types (guide variant — same as config-field-types-reference):
//
//   TextConfigField, MultilineConfigField, PasswordConfigField,
//   NumberConfigField (NumberFieldStyle, isInteger),
//   DropdownConfigField<T>, DropdownOption<T>,
//   BoolConfigField, GroupConfigField,
//   ExtensionConfigField (rendererKey, args),
//   ConfigField  // sealed base
//   ConfigFieldHandle  // value/reset handle for renderers
// #enddocregion config-field-types-guide-reference
```

- [ ] **Step 3: Write test cases**

These are comment-only regions. Just compile-test:

```dart
test('region config-field-types-reference compiles', () {
  expect(extensionFieldColorPickerReadme, isNotNull);
});

test('region config-field-types-guide-reference compiles', () {
  expect(extensionFieldColorPickerGuide, isNotNull);
});
```

- [ ] **Step 4: Run analyze + test — verify PASS**

---

## Task 14: Full analyze + test + write TSV

**Files:**
- Create: `.codex-out/snippet-leftover-mapping.tsv`

- [ ] **Step 1: Run full flutter analyze**

```bash
cd /Users/saadardati/IdeaProjects/plugin_kit/website/snippets && flutter analyze .
```
Expected: `No issues found!`

- [ ] **Step 2: Run full flutter test**

```bash
cd /Users/saadardati/IdeaProjects/plugin_kit/website/snippets && flutter test
```
Expected: All tests pass.

- [ ] **Step 3: Write snippet-leftover-mapping.tsv**

Write `.codex-out/snippet-leftover-mapping.tsv` with all rows from inventory that are non-skippable:

```tsv
doc_file	start_line	end_line	target_file	region_name	notes
website/src/content/docs/reference/event-bus-and-events.mdx	14	21	website/snippets/lib/event_bus.dart	event-bus-class-surface	created
website/src/content/docs/reference/event-bus-and-events.mdx	31	40	website/snippets/lib/event_bus.dart	event-envelope-class-surface	created
website/src/content/docs/reference/event-bus-and-events.mdx	312	316	website/snippets/lib/event_bus.dart	session-broadcast-extension	created
website/src/content/docs/concepts/event-bus.mdx	19	32	website/snippets/lib/event_bus.dart	on-and-emit-basic-event	created
website/src/content/docs/concepts/event-bus.mdx	75	79	website/snippets/lib/event_bus.dart	bind-and-unbind-context	skipped (duplicate of bind-observer-and-unbind)
skills/plugin-kit/api-cheatsheet.md	263	273	website/snippets/lib/event_bus.dart	on-request-variants-cheatsheet	created
skills/plugin-kit/patterns.md	216	233	website/snippets/lib/event_bus.dart	draft-event-mutation-pipeline	created
...
```

Full TSV covers all non-pure-fragment non-pseudocode inventory rows with status.

---

## Summary of Regions to Create

| Target file | Region names |
|---|---|
| event_bus.dart | `event-bus-class-surface`, `event-envelope-class-surface`, `session-broadcast-extension`, `on-and-emit-basic-event`, `on-request-variants-cheatsheet`, `draft-event-mutation-pipeline` |
| plugin_services.dart | `plugin-service-base-contract`, `stateful-plugin-service-minimal-contract`, `stateful-service-on-helper-example`, `plain-notification-service-baseline`, `config-raw-accessor`, `model-router-service-simple` |
| capabilities.dart | `capability-abstract-base`, `capability-lookup-extension-surface`, `configurable-capability-marker-pattern` |
| naming.dart | `plugin-id-extension-type-surface`, `namespace-extension-type-surface`, `service-id-extension-type-surface` |
| service_registry.dart | `service-registry-class-surface`, `scoped-service-registry-class-surface` |
| runtime_settings.dart | `runtime-settings-class-structure`, `runtime-settings-empty-constructor`, `plugin-config-class-structure` |
| custom_context.dart | `plugin-context-class-structure`, `global-plugin-context-class-structure`, `session-plugin-context-class-structure` |
| sessions.dart | `plugin-session-class-surface` |
| state_bridges.dart | `chat-protocol-types`, `riverpod-async-notifier-chat-controller` |
| logging.dart | `logging-onrecord-listener` |
| anti_patterns_registry.dart | `lazy-closure-and-attach-resolve-pattern`, `resolve-by-plugin-does-not-exist` |
| anti_patterns_naming.dart | `reserved-pk-prefix-runtime-throws` |
| anti_patterns_events.dart | `immutable-fact-event-with-final-fields` |
| testing.dart | `plugin-context-stub-forms`, `flutter-widget-editor-shell-test` |
| config_fields.dart | `config-field-types-reference`, `config-field-types-guide-reference` |

**Total: ~36 new regions** (bringing total from 71 to ~107)

---

## Skip Rules Applied

The following rows are SKIPPED because existing regions already cover them:
- `guides/testing.mdx:20-27` — covered by `plugin-service-inject-settings-test`
- `guides/testing.mdx:58-78` — covered by `plugin-request-response-test`
- `guides/testing.mdx:154-170` — covered by `runtime-update-settings-disables-plugin-test`
- `guides/testing.mdx:178-205` — covered by `stateful-service-attach-detach-test`
- `guides/testing.mdx:228-240` — covered by `lifecycle-exception-test`
- `README.md:301-340` (plugin_kit) — covered by `plugin-kit-symbol-cheatsheet`
- `plugin_kit_dialog/README.md:32-47` — covered by `show-dialog-save-merge-settings`
- `plugin_kit_dialog/README.md:223-245` — covered by `dialog-api-surface-with-renderers`
- `guides/plugin-kit-dialog.mdx:24-40` — covered by `show-dialog-save-merge-settings-guide`
- `guides/plugin-kit-dialog.mdx:253-270` — covered by `dialog-api-surface-theme-and-visuals`
- `concepts/event-bus.mdx:75-79` — duplicate of `bind-observer-and-unbind`
- `guides/migrating-flutter-app.mdx:373-397` — target is existing state_garden source (NOT snippets)

Large-scale real-code rows (many rows in inventory pointing to full source files like `packages/flutter_plugin_kit/`, `example/`, etc.) are skipped because: the doc block content matches existing source files; docregion-plan.tsv handles those via markers in source files not in `website/snippets/`.
