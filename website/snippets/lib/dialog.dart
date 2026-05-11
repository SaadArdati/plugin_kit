/// Snippets for PluginKitDialog widget usage, controller, save callback.
library;

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

/// Persists [settings] to disk or a backend.
Future<void> persistSettings(RuntimeSettings settings) async {
  // Implementation would write settings to disk.
  print(settings.plugins.length);
}

// #docregion dialog-show-dialog
Future<void> openConfigDialog(
  BuildContext context,
  PluginRuntime myRuntime,
  RuntimeSettings currentSettings,
) async {
  final next = await showPluginKitDialog(
    context: context,
    runtime: myRuntime,
    initialSettings: currentSettings,
    onSave: (settings) async {
      await persistSettings(settings); // write to disk, push to runtime, etc.
    },
  );
  if (next != null) {
    // User saved. `next` is the merged RuntimeSettings.
  }
}
// #enddocregion dialog-show-dialog

// #docregion dialog-show-dialog-themed
/// Demonstrates showPluginKitDialog with a custom [PluginKitDialogTheme].
Future<void> openConfigDialogThemed(
  BuildContext context,
  PluginRuntime myRuntime,
  RuntimeSettings settings,
  Future<void> Function(RuntimeSettings) persist,
) async {
  await showPluginKitDialog(
    context: context,
    runtime: myRuntime,
    initialSettings: settings,
    onSave: persist,
    theme: PluginKitDialogTheme.dark().copyWith(
      stableAccent: Colors.greenAccent,
      experimentalAccent: Colors.deepOrange,
    ),
  );
}
// #enddocregion dialog-show-dialog-themed

/// Stub service used in the dialog capability examples.
class MyService {
  /// Creates a [MyService].
  const MyService();
}

// #docregion dialog-ui-configurable-capability
void registerConfigurableService(ScopedServiceRegistry registry) {
  const agent = Namespace('agent');

  registry.registerSingleton<MyService>(
    agent('temperature'),
    () => const MyService(),
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
}
// #enddocregion dialog-ui-configurable-capability

// #docregion dialog-visuals-plugin
void addVisualsPlugin(PluginRuntime runtime, List<Plugin> myPlugins) {
  runtime
    ..addPlugins(myPlugins)
    ..addPlugin(
      PluginKitVisualsPlugin(
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
      ),
    );
}
// #enddocregion dialog-visuals-plugin

// #docregion dialog-extension-field
void registerWithExtensionField(ScopedServiceRegistry registry) {
  registry.registerSingleton<MyService>(
    const ServiceId('theme_service'),
    () => const MyService(),
    capabilities: const {
      UiConfigurableCapability(
        label: 'Theme',
        fields: [
          ExtensionConfigField(
            key: 'theme.accent',
            label: 'Accent color',
            rendererKey: 'color_picker',
            args: {'allow_alpha': false},
          ),
        ],
      ),
    },
  );
}
// #enddocregion dialog-extension-field

// #docregion dialog-color-picker-renderer
/// A custom field renderer for color values (Flutter-side).
class ColorPickerRenderer implements ConfigFieldRenderer<ExtensionConfigField> {
  /// Creates a [ColorPickerRenderer].
  const ColorPickerRenderer();

  @override
  Widget build(
    BuildContext context,
    ExtensionConfigField field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  ) {
    final allowAlpha = field.args['allow_alpha'] as bool? ?? false;
    return Slider(
      value: ((handle.value as int?) ?? 0xFF000000).toDouble(),
      min: 0,
      max: 0xFFFFFFFF.toDouble(),
      onChanged: (next) => handle.value = next.toInt(),
      label: allowAlpha ? 'ARGB' : 'RGB',
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
// #enddocregion dialog-color-picker-renderer

// #docregion dialog-reference-service-namespace
void registerWithNamespace(ScopedServiceRegistry registry) {
  const agent = Namespace('agent');

  registry.registerSingleton<MyService>(
    agent('temperature'),                  // ServiceId('agent.temperature')
    () => const MyService(),
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
}
// #enddocregion dialog-reference-service-namespace
