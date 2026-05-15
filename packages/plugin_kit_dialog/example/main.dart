// Minimal example: boot a PluginRuntime with two no-op plugins and open the
// plugin_kit_dialog via a button tap. The dialog inspects the live runtime,
// lets you toggle plugins and edit settings, and returns the updated
// RuntimeSettings on save.
//
// See packages/plugin_kit_dialog/README.md and the docs at
// https://plugin-kit-docs.saadodi44.workers.dev/ for the full guide.

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final PluginRuntime _runtime;
  RuntimeSettings _settings = const RuntimeSettings();

  @override
  void initState() {
    super.initState();
    _runtime = PluginRuntime(plugins: [_AlphaPlugin(), _BetaPlugin()])
      ..init(settings: _settings);
  }

  @override
  void dispose() {
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _openDialog(BuildContext context) async {
    final next = await showPluginKitDialog(
      context: context,
      runtime: _runtime,
      initialSettings: _settings,
      onSave: (settings) async {
        // Persist `settings` here (disk, remote, etc.) before the dialog
        // closes. This minimal example just lets the returned value flow
        // back via setState below.
      },
    );
    if (next != null && mounted) {
      setState(() => _settings = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'plugin_kit_dialog example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        appBar: AppBar(title: const Text('plugin_kit_dialog example')),
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => _openDialog(context),
              child: const Text('Open plugin_kit_dialog'),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlphaPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');

  @override
  void register(ScopedServiceRegistry registry) {}
}

class _BetaPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('beta');

  @override
  void register(ScopedServiceRegistry registry) {}
}
