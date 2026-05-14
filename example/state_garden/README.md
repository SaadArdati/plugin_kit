# state_garden

A workshop where the same plugin_kit chat protocol is bridged to seven
Flutter state management libraries side by side. Same plugin_kit soil,
seven different state-holder blooms.

This package is the source of citation for
[`docs/research/2026-05-04-flutter-state-management-integration.md`](../../docs/research/2026-05-04-flutter-state-management-integration.md)
and for the
[State Management Bridges](../../website/src/content/docs/reference/state-management-bridges.mdx)
guide. Every recipe described in those documents is implemented here,
executed under `flutter test`, and kept clean by `flutter analyze`. If a
future plugin_kit change quietly breaks one of the recipes, a test in this
package fails.

## What grows here

Ten integration recipes plus an `integration_launcher.dart` menu screen, all under [`lib/src/integrations/`](lib/src/integrations/):

- `setState` (no library)
- `flutter_plugin_kit` `PluginSessionStateListener` (the State-mixin
  variant of `setState` with subscription bookkeeping abstracted away)
- `plugin_kit` `PluginSessionListener` (the same mixin pattern wired
  directly from `plugin_kit` instead of `flutter_plugin_kit`)
- `ChangeNotifier` + `provider`
- `flutter_plugin_kit` `PluginEventNotifier` (a foundation
  `ChangeNotifier` / `ValueListenable` for "the latest event of type T",
  with no custom subclass to write)
- `flutter_bloc` Cubit
- Riverpod AsyncNotifier (with a `Provider<PluginSession>` overridden at
  app boot)
- `signals_flutter`
- MobX (no code generation)
- GetIt as a session locator

Each integration owns one bridge class (or one screen, for the
no-bridge variants) plus a screen widget. The ten screens render through
a shared [`ChatView`](lib/src/widgets/chat_view.dart) so the test harness
can type into the same key, tap the same key, and assert against the same
`MessageList` regardless of which bridge is under test.

Six lifecycle proofs (in
[`test/lifecycle_proofs_test.dart`](test/lifecycle_proofs_test.dart)),
written against pure plugin_kit APIs with no widgets:

- Settings reconcile: disabling a plugin via `updateSessionSettings`
  removes its event handlers but does not dispose the session bus or
  registry instances.
- Session swap: each session constructs its own service instances; an old
  session's service is frozen after `session.dispose`.
- Two live sessions stay isolated: messages emitted on one session never
  reach the other session's resolved `ChatService`.
- Canonical dispose: `runtime.dispose()` alone tears down session buses
  and drains the sessions list, with no need to call `session.dispose()`
  separately.
- Hot-swap: a higher-priority registrant wins resolution; disabling it
  via settings reconciliation flips the winner without touching the
  session.
- Toggle guard: two `updateSessionSettings` calls fired concurrently with
  `Future.wait` throw `StateError`; tail-chained serialization converges
  on the latest intent. Empirical proof of the runtime guard and
  serialization pattern called out in the research note.

## How to read the code

Start at [`lib/state_garden.dart`](lib/state_garden.dart) for the public
API surface. Then:

- [`lib/src/chat/`](lib/src/chat/) holds the chat protocol: `ChatMessage`,
  the two events, `ChatService` and `AltChatService`, and the two plugins
  that register them.

The chat service:

```dart
class ChatService extends StatefulPluginService {
  ChatService();

  final List<ChatMessage> _messages = <ChatMessage>[];

  /// Read-only view of accumulated messages. Test fixtures use this to
  /// verify per-session state isolation without going through the bus.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Bot reply prefix. Subclasses override to differentiate concrete
  /// services for hot-swap proofs without rewriting the subscription wiring.
  String get replyPrefix => 'echo: ';

  @override
  void attach() {
    on<SendMessageRequested>(_handleSend);
  }

  Future<void> _handleSend(EventEnvelope<SendMessageRequested> envelope) async {
    _messages.add(ChatMessage(author: 'user', text: envelope.event.text));
    _messages.add(
      ChatMessage(author: 'bot', text: '$replyPrefix${envelope.event.text}'),
    );
    await emit(ChatMessagesChanged(List<ChatMessage>.of(_messages)));
  }
}
```

- [`lib/src/widgets/`](lib/src/widgets/) holds the shared UI: a
  `MessageList`, a `MessageInput`, and a `ChatView` that composes them.
  No widget-returning helper methods anywhere.
- [`lib/src/integrations/`](lib/src/integrations/) holds one file per
  library, each documenting why the bridge is shaped that way.
- [`lib/src/runtime_holder.dart`](lib/src/runtime_holder.dart) is the
  test fixture and example boot path.
- [`lib/main.dart`](lib/main.dart) is the runnable demo: boots the
  runtime, wires the locators each integration expects, and renders the
  launcher.

## Running

From the workspace root:

```sh
flutter pub get
flutter test example/state_garden
flutter analyze example/state_garden
flutter run --target example/state_garden/lib/main.dart
```

## Architecture rules applied

- `ChatMessage` and `ChatBlocState` support value equality so observers
  do not rebuild on identical snapshots.
- Every async continuation that touches widget or holder state guards
  with `mounted`, `isClosed`, or a local `_disposed` flag, in line with
  the post-`await` discipline.
- Every visual chunk is a real `StatelessWidget` or `StatefulWidget`
  class. There are no widget-returning helper methods or top-level
  builders.
- Bridges depend on the abstract `PluginSession` type; nothing reaches
  past it into concrete plugin internals.
