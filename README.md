<p align="center">
  <img src="assets/logo-256.png" width="160" alt="Plugin Kit logo" />
</p>

# Plugin Kit

A Dart plugin runtime for apps that have grown into platforms: replaceable services, controlled plugin lifecycles, isolated sessions, and typed events between parts of your app that have never been formally introduced.

It has no opinion about what your app does. It does not know about Flutter, servers, agents, editors, or any particular settings backend. You build those on top. The runtime stays the same.

Plugins are wiring; services are the meat. The plugin class declares an id, registers services, and stays small. Real behavior, anything stateful or configurable or replaceable, lives in services.

![Plugin Kit Dialog showing the Plugins tab with toggleable enable/disable controls for each registered plugin](https://raw.githubusercontent.com/SaadArdati/plugin_kit/main/example/plugin_kit_dialog_demo/test/goldens/plugins_tab_dark.png)

*The `plugin_kit_dialog` companion package mounted on a real runtime. Toggling a tile runs the full lifecycle; the registry inspector and per-service config follow on the other tabs.*

## Packages in this repo

| Package | Adds |
|---|---|
| [`plugin_kit`](packages/plugin_kit) | Pure-Dart runtime: plugins, services, registry, event bus, settings, capabilities. The piece you build on. |
| [`flutter_plugin_kit`](packages/flutter_plugin_kit) | Flutter ergonomics: `InheritedWidget` scopes that carry the runtime/session through the tree, a `State` mixin that auto-cancels bus subscriptions across session swaps, a `ChangeNotifier` adapter, and `BuildContext.watchEvent` / `readEvent` extensions. Optional. |
| [`plugin_kit_dialog`](packages/plugin_kit_dialog) | Drop-in three-tab Flutter UI on top of any `PluginRuntime` for toggling plugins, editing configurable services, and browsing the registry. Optional. |

`plugin_kit` stands alone. The two Flutter packages are opt-in.

## Install

```yaml
dependencies:
  plugin_kit: ^1.0.0  <!-- pubver:plugin_kit -->
```

Requires Dart `>=3.10.0`. For Flutter projects that want the scope widgets and `State` mixin, also add [`flutter_plugin_kit`](packages/flutter_plugin_kit). For the customization UI, add [`plugin_kit_dialog`](packages/plugin_kit_dialog).

## A small taste

Two plugins claim the same `'greeter'` slot at different priorities. The runtime resolves to the winner. The host code never sees the competition.

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

Drop a plugin, lower its priority, or disable it through `RuntimeSettings`, and the call site never changes. That move, where features own slots and slots resolve to the current winner, is the vocabulary the rest of the library is built on.

## What's in plugin_kit

Plugins, services, registry, event bus, sessions, capabilities, settings reconciliation. The dart-only core covers all of it.

For the per-API breakdown with examples, see [`packages/plugin_kit/README.md`](packages/plugin_kit/README.md) or the full docs site below.

## Logging

plugin_kit uses `package:logging`. Lifecycle warnings, failed attaches, dependency cycles, and other diagnostics flow through named loggers (`plugin_kit.Plugin`, `plugin_kit.PluginRuntime`, `plugin_kit.PluginSession`). Nothing is printed by default; attach a listener to the root logger to see them:

```dart
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.INFO; // or Level.ALL during development
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.loggerName}: ${record.message}');
    if (record.error != null) print('  ${record.error}');
    if (record.stackTrace != null) print(record.stackTrace);
  });

  runApp(MyApp());
}
```

Without a listener configured, severe-level messages (failed plugin attach, detected dependency cycles, etc.) go nowhere; you'll see the runtime continue past the failure but won't know why. Wire up a listener at app startup, or route to your existing logging stack.

## Documentation

- **Full docs**: [plugin-kit-docs.saadodi44.workers.dev](https://plugin-kit-docs.saadodi44.workers.dev). Concepts, guides, tutorials, reference.
- **Examples**: [`example/`](example). `villain_lair/` is a numbered-bin tour through every primitive; `model_embassy/` walks competing providers, capabilities, and reconciliation; `state_garden/` shows the same chat pattern bridged to seven Flutter state-management libraries; `code_editor/` is a full Flutter capstone; `plugin_kit_dialog_demo/` runs the dialog over a 21-plugin runtime.
- **Source**: this repo. Issues and discussions on [GitHub](https://github.com/SaadArdati/plugin_kit).

## License

Copyright (c) 2026, Saad Ardati. Released under the BSD 3-Clause License. See [LICENSE](LICENSE).
