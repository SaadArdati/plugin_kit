<p align="center">
  <img src="https://raw.githubusercontent.com/SaadArdati/plugin_kit/main/assets/flutter_plugin_kit-256.png" width="160" alt="flutter_plugin_kit logo" />
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_plugin_kit"><img src="https://img.shields.io/pub/v/flutter_plugin_kit.svg" alt="pub package" /></a>
  <a href="https://github.com/SaadArdati/plugin_kit/blob/main/packages/flutter_plugin_kit/LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg" alt="License: BSD-3-Clause" /></a>
</p>

Skip the boilerplate of plumbing [`plugin_kit`](https://pub.dev/packages/plugin_kit) through your widget tree. `flutter_plugin_kit` adds scope widgets that carry the runtime and session, a `State` mixin that auto-cancels event subscriptions, a `ChangeNotifier` adapter, and `BuildContext` extensions for reading the latest event of any type.

The exposed types implement standard Flutter `ChangeNotifier` / `ValueListenable` / `Stream` interfaces, so they drop into `provider`, `flutter_bloc`, `riverpod`, signals, and others as ordinary values. Use only the adapters your app already needs, or skip a state library entirely and use the bus directly.

Pulls in only `flutter` and `plugin_kit`.

## What's in the box

- `PluginRuntimeScope`: `InheritedWidget` carrying a `PluginRuntime`. Either pass an externally-owned runtime via `.value`, or pass a list of plugins and let the scope construct, init, and dispose one for you.
- `PluginSessionScope`: `InheritedWidget` carrying a `PluginSession`. Three modes: explicit session, runtime + auto-create session, or derive both from an ambient `PluginRuntimeScope`. Async session creation is handled with optional `loading` and `error` builders.
- `PluginSessionStateListener<W>`: mixin on `State<W>`. `listen<E>(handler)` and `rebuildOn<E>([when])` register subscriptions that auto-cancel on dispose and re-attach automatically across session swaps. Both are callable from `initState` (and any later lifecycle callback). By default the mixin reads the active session from the ambient `PluginSessionScope`; override `PluginSession? get session` only when the session lives elsewhere (typically `=> widget.session`).
- `PluginEventNotifier<E>`: `ChangeNotifier` / `ValueListenable<E?>`. Subscribes to a session and exposes the latest event of type `E` as `.value`. Drops directly into `ChangeNotifierProvider`, `ValueListenableProvider`, `ValueListenableBuilder`, or any other foundation-listenable consumer.
- `BuildContext.watchEvent<E>()` / `readEvent<E>()`: convenience extensions. `watchEvent` subscribes the calling element to rebuilds on the next `E`; `readEvent` returns the latest without subscribing.

## Quick tour

`ChatPlugin`, `AssistantPlugin`, and `ChatMessageReceived` below are stand-ins for plugins and events you write in your own app. A complete runnable version of this pattern (plus six other state-library variants) lives in [`example/state_garden/`](https://github.com/SaadArdati/plugin_kit/tree/main/example/state_garden).

```dart
void exampleAppRoot() {
  runApp(
    MaterialApp(
      home: PluginRuntimeScope(
        plugins: [ChatPlugin(), AssistantPlugin()],
        child: const PluginSessionScope(child: ChatScreen()),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
  /// Creates a [ChatScreen].
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with PluginSessionStateListener<ChatScreen> {
  String? _last;

  @override
  void initState() {
    super.initState();
    listen<ChatMessageReceived>((event) {
      setState(() => _last = event.text);
    });
  }

  @override
  Widget build(BuildContext context) => Text(_last ?? 'idle');
}
```

The `Builder`-only variant is even shorter:

```dart
Widget buildWatchEventExample() {
  return Builder(
    builder: (context) {
      final last = context.watchEvent<ChatMessageReceived>();
      return Text(last?.text ?? 'idle');
    },
  );
}
```

## Integrating with state-management libraries

`flutter_plugin_kit` does not depend on `provider`, `flutter_bloc`, or any other state library. It exposes standard Flutter shapes that those libraries already consume.

### provider

`PluginEventNotifier<E>` is a `ChangeNotifier`, so it drops into `ChangeNotifierProvider` directly:

```dart
ChangeNotifierProvider(
  create: (context) => PluginEventNotifier<ChatMessageReceived>(
    PluginSessionScope.of(context),
  ),
  child: const ChatBody(),
);

// In ChatBody:
final last = context.watch<PluginEventNotifier<ChatMessageReceived>>().value;
```

It also implements `ValueListenable<E?>`, so `ValueListenableProvider`, `ValueListenableBuilder`, and `Listenable.merge` all work without ceremony.

### flutter_bloc

No Cubit adapter is bundled; create one by subscribing to `session.on<E>`:

```dart
/// Example Bloc-style cubit that bridges session events.
class PluginEventCubit<E> {
  /// The current event value.
  E? value;

  late final EventSubscription _sub;

  /// Creates a cubit listening to [session] for events of type [E].
  PluginEventCubit(PluginSession session) {
    _sub = session.on<E>((envelope) {
      value = envelope.event;
    });
  }

  /// Cancels the subscription.
  void close() {
    _sub.cancel();
  }
}
```

Wrap with `BlocProvider` and read with `context.watch<PluginEventCubit<ChatMessageReceived>>().state`. The full recipe (with value-equality state classes) lives in [`example/state_garden/lib/src/integrations/bloc_chat.dart`](https://github.com/SaadArdati/plugin_kit/blob/main/example/state_garden/lib/src/integrations/bloc_chat.dart).

### riverpod / signals / mobx

The same pattern applies: subscribe in a notifier or store, expose the latest event, dispose cancels. Each library's recipe lives in [`example/state_garden/`](https://github.com/SaadArdati/plugin_kit/tree/main/example/state_garden).

## Lifecycle notes

`PluginRuntimeScope` and `PluginSessionScope` only own the runtime/session when they constructed it themselves. Pass an external one via `.value` or the `session:` / `runtime:` arguments and the caller keeps lifecycle control, same contract as `Provider.value`.

`PluginRuntime` and `PluginSession` are designed to outlive the widget tree (hot restart, route stack resets, deep navigation). For long-lived runtimes, hold the runtime outside the tree (top-level final, GetIt singleton, Riverpod provider with one-shot create) and pass it into `PluginRuntimeScope.value` / `PluginSessionScope(session: ...)`. Use the auto-create variants only when the scope's lifetime is the runtime's lifetime, e.g., a per-route `StatefulWidget`.

## Related packages

- [`plugin_kit`](https://pub.dev/packages/plugin_kit): the dart-only runtime this package layers on top of. Required.
- [`plugin_kit_dialog`](https://pub.dev/packages/plugin_kit_dialog): drop-in three-tab Flutter UI for inspecting and editing any `PluginRuntime`. Composes naturally with the scopes shipped here.

## Documentation

- **Full docs**: [plugin-kit-docs.saadodi44.workers.dev/guides/flutter-plugin-kit/](https://plugin-kit-docs.saadodi44.workers.dev/guides/flutter-plugin-kit/). The dedicated guide.
- **API reference**: [pub.dev dartdoc](https://pub.dev/documentation/flutter_plugin_kit/latest/).
- **Source and issues**: [github.com/SaadArdati/plugin_kit](https://github.com/SaadArdati/plugin_kit).

## License

BSD 3-Clause. See [LICENSE](https://github.com/SaadArdati/plugin_kit/blob/main/packages/flutter_plugin_kit/LICENSE).
