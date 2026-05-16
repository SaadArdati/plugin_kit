# plugin_kit_dialog_demo

A runnable Flutter showcase for [`plugin_kit_dialog`](../../packages/plugin_kit_dialog).

**Live demo:** [plugin-kit.saad-ardati.dev/dialog](https://plugin-kit.saad-ardati.dev/dialog)

The demo wires together 20 competing plugins (priority towers on `agent.model`,
`agent.system_message`, `retry.policy`, and `search.provider`, plus locked and
experimental tiers) and one `PluginKitVisualsPlugin` decorating every plugin,
namespace, and service (21 total runtime plugins). Mounting `showPluginKitDialog(...)` exposes the
three-tab UI (Plugins, Services, Advanced) against this synthetic runtime, so
you can poke at toggle behavior, priority overrides, capability chips, and the
registry inspector without setting up a real product.

## Run

```sh
flutter run --target lib/main.dart
```

From the workspace root:

```sh
flutter run --target example/plugin_kit_dialog_demo/lib/main.dart
```

## What's inside

- `lib/main.dart`: boots the runtime, mounts a `Scaffold` that opens
  `showPluginKitDialog`, and surfaces the merged `RuntimeSettings`
  returned by the dialog.
- `lib/plugins/`: the 21 demo plugins, grouped by namespace and tier.
- `lib/plugin_visuals.dart`: the `PluginKitVisualsPlugin` decorating each
  axis (plugin, namespace, service).

## Companion documentation

- [`plugin_kit_dialog` README](../../packages/plugin_kit_dialog/README.md)
- [Plugin Kit Dialog guide](https://plugin-kit.saad-ardati.dev/guides/plugin-kit-dialog/)
- [Dialog API reference](https://plugin-kit.saad-ardati.dev/reference/dialog-api/)

The screenshots that ship with the dialog docs are golden-tested against
this demo, so what you see in the docs is exactly what `flutter run` here
renders.
