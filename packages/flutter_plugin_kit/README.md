<p align="center">
  <img src="../../assets/logo-256.png" width="160" alt="Plugin Kit logo" />
</p>

# flutter_plugin_kit

Flutter ergonomics on top of [`plugin_kit`](../plugin_kit). Scope widgets that carry the runtime and session through the tree, a `State` mixin that handles bus subscriptions, a `ChangeNotifier` adapter for state-management libraries, and `BuildContext` extensions for reading the latest event of a given type.

Pulls in only `flutter` and `plugin_kit`. The exposed types implement standard Flutter `ChangeNotifier` / `ValueListenable` / `Stream` interfaces, so they drop into `provider`, `flutter_bloc`, `riverpod`, signals, etc. as ordinary values — wire them through whatever you already have, or skip a state library entirely and use the bus directly. Pick the combination that pays for itself.

## What's in the box

- `PluginRuntimeScope` — `InheritedWidget` carrying a `PluginRuntimeManager`. Either pass an externally-owned manager via `.value`, or pass a list of plugins and let the scope construct, init, and dispose one for you.
- `PluginSessionScope` — `InheritedWidget` carrying a `PluginSession`. Three modes: explicit session, runtime + auto-create session, or derive both from an ambient `PluginRuntimeScope`. Async session creation is handled with optional `loading` and `error` builders.
- `PluginSessionStateListener<W>` — mixin on `State<W>`. `listen<E>(handler)` and `rebuildOn<E>([when])` register subscriptions that auto-cancel on dispose and re-attach automatically across session swaps. Both are callable from `initState` (and any later lifecycle callback) — no `_wired` guard needed. By default the mixin reads the active session from the ambient `PluginSessionScope`; override `PluginSession? get session` only when the session lives elsewhere (typically `=> widget.session`).
- `PluginEventNotifier<E>` — `ChangeNotifier` / `ValueListenable<E?>`. Subscribes to a session and exposes the latest event of type `E` as `.value`. Drops directly into `ChangeNotifierProvider`, `ValueListenableProvider`, `ValueListenableBuilder`, or any other foundation-listenable consumer.
- `BuildContext.watchEvent<E>()` / `readEvent<E>()` — convenience extensions. `watchEvent` subscribes the calling element to rebuilds on the next `E`; `readEvent` returns the latest without subscribing.

## Quick tour

```dart
import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  runApp(
    MaterialApp(
      home: PluginRuntimeScope(
        plugins: [ChatPlugin(), AssistantPlugin()],
        child: const PluginSessionScope(
          child: ChatScreen(),
        ),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
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
Builder(
  builder: (context) {
    final last = context.watchEvent<ChatMessageReceived>();
    return Text(last?.text ?? 'idle');
  },
);
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

There's no shipped Cubit adapter — it's eight lines you write yourself, parameterised by whatever `Bloc` shape your app prefers:

```dart
class PluginEventCubit<E> extends Cubit<E?> {
  PluginEventCubit(PluginSession session) : super(null) {
    _sub = session.on<E>((envelope) {
      if (!isClosed) emit(envelope.event);
    });
  }
  late final StreamSubscription<void> _sub;

  @override
  Future<void> close() async {
    _sub.cancel();
    return super.close();
  }
}
```

Wrap with `BlocProvider` and read with `context.watch<PluginEventCubit<ChatMessageReceived>>().state`. See `example/state_garden` for the full recipe with state classes and value equality.

### riverpod / signals / mobx

Same shape: subscribe in a notifier or store, expose the latest event, dispose cancels. Each library's recipe lives in `example/state_garden/`.

## Lifecycle notes

`PluginRuntimeScope` and `PluginSessionScope` only own the runtime/session when they constructed it themselves. Pass an external one via `.value` or the `session:` / `runtime:` arguments and the caller keeps lifecycle control — same contract as `Provider.value`.

`PluginRuntimeManager` and `PluginSession` are designed to outlive the widget tree (hot restart, route stack resets, deep navigation). For long-lived runtimes, hold the manager outside the tree (top-level final, GetIt singleton, Riverpod provider with one-shot create) and pass it into `PluginRuntimeScope.value` / `PluginSessionScope(session: ...)`. The auto-create variants are convenient when the scope's lifetime really does match the runtime's, e.g. inside a per-route `StatefulWidget`.
