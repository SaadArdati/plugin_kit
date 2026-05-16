<p align="center">
  <img src="assets/logo-256.png" width="160" alt="Plugin Kit logo" />
</p>

# Plugin Kit

A Dart plugin runtime for apps that have grown into platforms. Features get real lifecycles. Services get replaceable, prioritized implementations. Sessions stay sealed. Behavior gets to be replaced, layered, disabled, overridden, or vetoed while the app is running.

It does not know about Flutter, servers, agents, editors, or any particular settings backend. You build those on top. The runtime stays the same.

> A DI container answers *"give me an instance of X."*
> A plugin runtime answers a different question: *"given this set of capabilities, this user's settings, and this session's scope, compose a coherent system and let me change my mind at any time."*

The difference is composition. DI wires up a fixed graph at startup. A plugin runtime wires up a dynamic graph that responds to settings changes, plugin enable/disable, priority overrides, and session boundaries while the application is running.

![Plugin Kit Dialog showing the Plugins tab with toggleable enable/disable controls for each registered plugin](https://raw.githubusercontent.com/SaadArdati/plugin_kit/main/example/plugin_kit_dialog_demo/test/goldens/plugins_tab_dark.png)

*The `plugin_kit_dialog` companion package mounted on a real runtime. Toggling a tile runs the full lifecycle.*

## Most apps don't need this

If your app has one HTTP client, one auth service, one analytics service, and a few screens that call them, use the boring thing. Instantiate the client. Register the service. Ship the app.

Plugin Kit starts making sense at the exact moment the word "just" starts lying to you. *"Just add a setting to disable this provider." "Just let enterprise customers override this behavior." "Just experiment quickly with this implementation." "Just make sure the original runs if this way fails."* When behavior needs to be replaced, layered, disabled, overridden, or vetoed while the app is running, and settings have stopped being data your app reads and started being something that actively reshapes the system, you have outgrown a DI container. That is the seam this library is for.

## Packages in this repo

| Package | Adds | Add when |
|---|---|---|
| [`plugin_kit`](packages/plugin_kit) | Pure-Dart runtime: plugins, services, registry, event bus, settings, capabilities. | Always. The thing you build on. |
| [`flutter_plugin_kit`](packages/flutter_plugin_kit) | `InheritedWidget` scopes that carry the runtime/session, a `State` mixin that auto-cancels bus subscriptions across session swaps, a `ChangeNotifier` adapter, `BuildContext.watchEvent`/`readEvent` extensions. | Your shell is Flutter and you want the widget plumbing done. |
| [`plugin_kit_dialog`](packages/plugin_kit_dialog) | Drop-in three-tab Flutter UI: toggle plugins, edit configurable services, browse the registry. | Your users (or your QA) need to flip plugins at runtime without you writing a settings screen per plugin. |

The Dart-only core stays Dart-only on purpose: a backend Dart package can declare its `UiConfigurableCapability` once and any Flutter app that ships `plugin_kit_dialog` will render a real settings UI for it, without the backend taking a Flutter dependency.

## A taste

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

At the call site:

```dart
final greeter = session.resolve<Greeter>(const ServiceId('greeter'));
print(greeter.greet(name));
```

No conditional, no flag, no branch. Drop the formal plugin, lower its priority, or disable it through `RuntimeSettings`, and the call site never changes. That move, where features own slots and slots resolve to the current winner, is the vocabulary the rest of the library is built on.

## What this actually buys you: less breakable code

Plugin Kit makes a class of bugs structurally impossible rather than situationally avoidable.

- `attach` and `detach` are framework-enforced. Subscriptions opened during `attach` on a `StatefulPluginService` are tracked and cancelled after `detach` returns. "I forgot to cancel that subscription" stops being a bug class.
- Lifecycle failures aggregate. `PluginLifecycleException` carries the named phase (`attachGlobal`, `attachSession`, `updateSessionSettings`) and every plugin's error. One plugin throwing at startup does not abort the others; it surfaces as part of a labelled aggregate.
- `enabledPlugins` (settings-intent) and `attachedPlugins` (post-dependency-cascade runtime-truth) are distinct, queryable sets. A plugin whose dependency went missing does not silently advertise itself as running.
- Reconciliation is transactional. Per-plugin attach failures roll back to honest state (failed plugin out of the enabled set, services unregistered), and `updateSettings` rolls every reconciled session and the global scope back to the previous snapshot on any mid-loop failure. The stored `RuntimeSettings` snapshot stays at the previous value, so the caller never sees split-brain.

You stop writing the teardown code, and the runtime stops trusting you to write it correctly.

## State management vs Plugin Kit

State management owns presentation state. Plugin Kit owns participation. A chat screen showing messages is presentation state. A plugin deciding whether it wants to enrich an outgoing prompt is participation. Plugin Kit sits beside Provider, Riverpod, Bloc, or GetIt: they keep doing widget-facing work; Plugin Kit owns the runtime protocol underneath.

## Logging

plugin_kit uses `package:logging`. Lifecycle warnings, failed attaches, dependency cycles, and other diagnostics flow through named loggers (`plugin_kit.Plugin`, `plugin_kit.PluginRuntime`, `plugin_kit.PluginSession`). Nothing is printed by default; attach a listener to the root logger to see them. Add `package:logging/logging.dart` to your imports, then in your app's `main()`:

```dart
void main() {
  Logger.root.level = Level.INFO; // or Level.ALL during development
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
    if (record.error != null) print('  ${record.error}');
    if (record.stackTrace != null) print(record.stackTrace);
  });

  runApp(const MyApp());
}
```

Without a listener configured, severe-level messages (failed plugin attach, detected dependency cycles, etc.) go nowhere; you'll see the runtime continue past the failure but won't know why. Wire up a listener at app startup, or route to your existing logging stack.

## Documentation

- **Full docs**: [plugin-kit-docs.saadodi44.workers.dev](https://plugin-kit-docs.saadodi44.workers.dev). Concepts, guides, tutorials, reference.
- **Examples**: [`example/`](example). `villain_lair/` is a numbered-bin tour through every primitive; `model_embassy/` walks competing providers, capabilities, and reconciliation; `state_garden/` shows the same chat pattern bridged to seven Flutter state-management libraries ([live demo](https://plugin-kit-state-garden.pages.dev)); `code_editor/` is a full Flutter capstone ([live demo](https://plugin-kit-code-editor.pages.dev)); `plugin_kit_dialog_demo/` runs the dialog over a 21-plugin runtime ([live demo](https://plugin-kit-dialog-demo.pages.dev)).
- **Source**: this repo. Issues and discussions on [GitHub](https://github.com/SaadArdati/plugin_kit).

## License

Copyright (c) 2026, Saad Ardati. Released under the BSD 3-Clause License. See [LICENSE](LICENSE).
