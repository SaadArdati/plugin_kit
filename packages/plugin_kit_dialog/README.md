<p align="center">
  <img src="../../assets/logo-256.png" width="160" alt="Plugin Kit logo" />
</p>

# plugin_kit_dialog

A Flutter dialog that inspects and edits any [`plugin_kit`](../plugin_kit) `PluginRuntime` at runtime. Drop it in once
and your users get a three-tab UI for toggling plugins, editing service fields, and inspecting the registry, without
you writing a settings screen per plugin set.

```
┌──────────────────────────────────────────────────────────────┐
│  Plugins   Services    Advanced              Cancel   Save  │
├──────────────────────────────────────────────────────────────┤
│  ○ chat_manager · stable                                ●   │
│  ○ enterprise_chat · stable                             ●   │
│  ○ debug_overrides · experimental                       ○   │
│  ...                                                         │
└──────────────────────────────────────────────────────────────┘
```

- **Plugins tab**: enable/disable each plugin; locked entries can't be toggled, experimental ones are flagged.
- **Services tab**: every service that ships a `UiConfigurableCapability` becomes an editable card. Edit text,
  numbers, dropdowns, switches, multiline, password, grouped, or custom fields.
- **Advanced tab**: registry inspector with priority chains, winners, shadowed contenders, plus a JSON view of the
  working settings.

The dialog is wholly **dogfooded**: it builds itself out of `plugin_kit` plugins, so every tab, header action,
and field renderer is a real plugin you can shadow or replace from your host app.

## Install

```yaml
dependencies:
  plugin_kit: ^1.0.0
  plugin_kit_dialog: ^0.1.0
```

`plugin_kit` carries the dart-only declaration types (`UiConfigurableCapability`, `ConfigField`, etc). `plugin_kit_dialog` adds the Flutter UI.

## Quick start

```dart
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

final next = await showPluginKitDialog(
  context: context,
  runtime: myRuntime, // your PluginRuntime
  initialSettings: currentSettings,
  onSave: (settings) async {
    await persistSettings(settings); // write to disk, push to runtime, etc.
  },
);
if (next != null) {
  // User saved. `next` is the merged RuntimeSettings.
}
```

That's it. If your plugins already attach `UiConfigurableCapability`, the Services tab populates itself.

## Declaring configurable services

Configurability is opt-in per registration. Attach a `UiConfigurableCapability` next to any service:

```dart
// In your plugin's register(). This code can live in a Dart-only package.
const agent = Namespace('agent');

registry.registerSingleton<MyService>(
  agent('temperature'),
  MyService(),
  capabilities: const {
    UiConfigurableCapability(
      label: 'Temperature',
      description: 'Controls randomness in responses.',
      fields: [
        NumberConfigField(
          key: 'temperature',
          label: 'Temperature',
          min: 0,
          max: 2,
          step: 0.1,
          defaultValue: 1.0,
        ),
      ],
    ),
  },
);
```

Saved values flow through `RuntimeSettings.services[Pin('main_agent', ['agent', 'temperature'])].config` (or the typed chain `pluginId.namespace('agent').service('temperature')`).

### Built-in field types

All live in `plugin_kit` (Dart-only):

| Field                    | Renders as                                                                                                                                                                            |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `TextConfigField`        | Single-line `TextField`.                                                                                                                                                              |
| `MultilineConfigField`   | Multiline editor with optional moustache-tag chips.                                                                                                                                   |
| `PasswordConfigField`    | Obscured input with show/hide toggle.                                                                                                                                                 |
| `NumberConfigField`      | Slider when both `min` and `max` set; numeric `TextField` otherwise. `style: NumberFieldStyle.textInput` forces text mode. `isInteger: true` stores `int` and snaps to whole numbers. |
| `DropdownConfigField<T>` | Typed dropdown over `List<DropdownOption<T>>`.                                                                                                                                        |
| `BoolConfigField`        | Switch with label + helper.                                                                                                                                                           |
| `GroupConfigField`       | Indented sub-section grouping nested fields under a heading.                                                                                                                          |
| `ExtensionConfigField`   | Escape hatch for custom Flutter renderers (see below).                                                                                                                                |

Each field carries `key`, `label`, `helperText`, and `defaultValue`. Dotted keys (`provider.api_key`) write to nested maps automatically.

## Visuals (icons, colors, labels)

Visuals are a Flutter-only concern, so the canonical attachment path is one locked `GlobalPlugin` — `PluginKitVisualsPlugin` — that the host app adds to the runtime alongside its other plugins. It carries three independent maps for the three things the dialog renders: plugin tiles, namespace section headers, and individual service cards.

```dart
runtime
  ..addPlugins([...myPlugins])
  ..addPlugin(PluginKitVisualsPlugin(
    pluginVisuals: {
      const PluginId('main_agent'): const PluginKitVisual(
        label: 'Main Agent',
        description: 'The brain. Drives chat, tools, and routing.',
        icon: Icon(Icons.psychology),
        color: Color(0xFF7C5CFF),
      ),
    },
    namespaceVisuals: {
      const Namespace('agent'): const PluginKitVisual(
        label: 'Agent',
        icon: Icon(Icons.smart_toy),
        color: Color(0xFF7C5CFF),
      ),
    },
    serviceVisuals: {
      const Namespace('agent')('temperature'): const PluginKitVisual(
        label: 'Temperature',
        icon: Icon(Icons.thermostat),
        color: Color(0xFFFF9500),
      ),
    },
  ));
```

Because the visuals plugin lives in your host app (which has Flutter), Dart-only plugins still get rich visuals without importing Flutter. The decoration is keyed by `PluginId`, `Namespace`, or `ServiceId`, so the host owns the map and the plugin source code stays portable. Unknown keys (a plugin or service that doesn't currently exist) are accepted silently; this lets you keep visuals for plugins that may be enabled later. When no visual is found, cards fall back to a generic gear icon and the theme's primary color.

## Custom field renderers

Need a color picker, file selector, or any other widget? Declare an `ExtensionConfigField` from anywhere (no Flutter needed at the field site):

```dart
// In your dart-only plugin.
const ExtensionConfigField(
  key: 'theme.accent',
  label: 'Accent color',
  rendererKey: 'color_picker',
  args: {'allow_alpha': false},
)
```

Register a Flutter-side renderer for that key from your host app:

```dart
class ColorPickerRenderer
    implements ConfigFieldRenderer<ExtensionConfigField> {
  const ColorPickerRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) {
    final allowAlpha = field.args['allow_alpha'] as bool? ?? false;
    return ColorPicker(
      value: handle.value as int? ?? 0xFF000000,
      onChanged: (next) => handle.value = next,
      allowAlpha: allowAlpha,
    );
  }
}

class ColorPickerRendererPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('color_picker_renderer');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<ConfigFieldRenderer>(
      FieldRenderersPlugin.namespace('color_picker'),
      ColorPickerRenderer.new,
    );
  }
}
```

If a renderer key is unknown when the dialog tries to resolve it, an inline placeholder card surfaces the missing key; the dialog never throws at paint time.

## Theming

Pass a `PluginKitDialogTheme` to override accents, surfaces, and badges:

```dart
showPluginKitDialog(
  context: context,
  runtime: myRuntime,
  initialSettings: settings,
  onSave: persist,
  theme: PluginKitDialogTheme.dark().copyWith(
    stableAccent: Colors.greenAccent,
    experimentalAccent: Colors.deepOrange,
  ),
);
```

Or wrap your app with `buildPluginKitDialogDarkTheme()` / `buildPluginKitDialogLightTheme()` to adopt the full Material 3 `ThemeData`.

## Why dart-only declaration matters

The capability + field types live in `plugin_kit`, **not** in this package. That means a non-Flutter package (server-side, CLI, shared `common/` library) can declare configurable services without taking a Flutter dependency. The Flutter UI layers on top through:

- `PluginKitVisualsPlugin` (Flutter, host-app side) for icons, labels, and colors across the plugin, namespace, and service axes,
- `ExtensionConfigField` + a registered Flutter renderer for custom widgets.

That keeps your shared plugin packages portable. The host app owns the Flutter-only glue.

## Saving and dirty state

The dialog is **non-destructive**. Edits accumulate in a working draft; nothing reaches the runtime until the user hits **Save**. `onSave` receives the merged `RuntimeSettings`; persist it however you like. Cancel discards the draft (with a confirm prompt if dirty). Overrides that match the active baseline are pruned automatically, so `RuntimeSettings` stays minimal.

## Example app

A runnable demo with 20 competing plugins (priority towers on `agent.model`, `agent.system_message`, `retry.policy`, `search.provider`, plus locked and experimental tiers) plus one `PluginKitVisualsPlugin` decorating every plugin, namespace, and service (21 total runtime plugins) lives at [`example/plugin_kit_dialog_demo`](../../example/plugin_kit_dialog_demo). Run it with `flutter run` from that directory.

## Public API

```dart
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

// Entry points
showPluginKitDialog(...);            // Future<RuntimeSettings?>
PluginKitDialog(...);                // raw widget (custom hosting)
PluginKitDialogBody(...);            // tab body (custom chrome)
PluginKitDialogController(...);      // ChangeNotifier-backed draft

// Visuals
PluginKitVisualsPlugin({pluginVisuals, namespaceVisuals, serviceVisuals});
PluginKitVisual(label, description, icon, color);

// Field renderers (custom widgets via ExtensionConfigField)
FieldRenderersPlugin;                // namespace under which renderers register
ConfigFieldRenderer<F extends ConfigField>;
FieldRenderResolver;                 // (rendererKey) -> ConfigFieldRenderer?

// Theme
buildPluginKitDialogDarkTheme();
buildPluginKitDialogLightTheme();
PluginKitDialogTheme;                // ThemeExtension
```

Declarative types come from `plugin_kit`:

```dart
import 'package:plugin_kit/plugin_kit.dart';

UiConfigurableCapability(label, fields, description);
TextConfigField, MultilineConfigField, PasswordConfigField,
NumberConfigField (NumberFieldStyle, isInteger),
DropdownConfigField<T>, DropdownOption<T>,
BoolConfigField, GroupConfigField,
ExtensionConfigField (rendererKey, args),
ConfigField                          // sealed base
ConfigFieldHandle                    // value/reset handle for renderers
```

## Design spec

Full architectural notes: [`docs/superpowers/specs/2026-04-24-plugin-kit-dialog-design.md`](../../docs/superpowers/specs/2026-04-24-plugin-kit-dialog-design.md).
