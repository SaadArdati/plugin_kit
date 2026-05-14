# flutter_plugin_kit_example

A small live demo of every reading path in
[`flutter_plugin_kit`](../) on a single screen. Two plugins drive the
display: a `TickerPlugin` heartbeat and a `CounterPlugin` whose value steps
on user intent.

The four cards correspond to the four exposed reading paths:

1. `ClockCard`: `BuildContext.watchEvent<TickEvent>()` inside a
   `StatelessWidget`. Smallest possible call site.
2. `CounterCard`: `PluginSessionScope.of(context).emit(...)` plus
   `context.watchEvent<CounterChanged>()`. User intents go in, plugin
   state comes back out.
3. `HistoryCard`: `SessionListener` mixin on a `State` subclass with
   `listen<TickEvent>`. Subscriptions are cancelled in `dispose`
   automatically; the example keeps a rolling window of recent ticks.
4. `NotifierCard`: `PluginEventNotifier<TickEvent>` consumed through a
   `ValueListenableBuilder`. Same shape that drops directly into
   `ChangeNotifierProvider`, `ValueListenableProvider`, etc., without
   `flutter_plugin_kit` taking a dependency on any of them.

## Run

```sh
cd packages/flutter_plugin_kit/example
flutter pub get
flutter run -d chrome    # or any other configured device
```

If platform scaffolding is missing for your target, add it first:

```sh
flutter create --platforms=web,macos .
```
