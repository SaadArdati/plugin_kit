import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog_demo/plugin_visuals.dart';
import 'package:plugin_kit_dialog_demo/plugins/all.dart';

/// Entry point for the demo app.
void main() => runApp(const PluginKitDialogDemoApp());

/// Demo Flutter app that wires [showPluginKitDialog] to a real [PluginRuntime].
class PluginKitDialogDemoApp extends StatefulWidget {
  /// Creates the demo app.
  const PluginKitDialogDemoApp({super.key});

  @override
  State<PluginKitDialogDemoApp> createState() => _PluginKitDialogDemoAppState();
}

class _PluginKitDialogDemoAppState extends State<PluginKitDialogDemoApp> {
  static const _jsonEncoder = JsonEncoder.withIndent('  ');

  late final PluginRuntime _runtime;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  RuntimeSettings _settings = RuntimeSettings();
  String _settingsPreview = _jsonEncoder.convert(RuntimeSettings().toJson());

  @override
  void initState() {
    super.initState();
    _runtime = PluginRuntime()
      ..addPlugins(demoPlugins())
      ..addPlugin(visualsPlugin())
      ..init(settings: RuntimeSettings());
  }

  @override
  void dispose() {
    _runtime.dispose();
    super.dispose();
  }

  Future<void> _openDialog() async {
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      return;
    }

    final next = await showPluginKitDialog(
      context: dialogContext,
      runtime: _runtime,
      initialSettings: _settings,
      onSave: (_) async {
        // Placeholder persistence: in a real app, write to disk / push to the runtime.
        // For the demo, the returned value is the final settings; onSave is a callback
        // that lets hosts do work *before* the dialog closes.
      },
    );
    if (next != null && mounted) {
      setState(() {
        _settings = next;
        _settingsPreview = _jsonEncoder.convert(next.toJson());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'plugin_kit_dialog demo',
      debugShowCheckedModeBanner: false,
      theme: buildPluginKitDialogDarkTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('plugin_kit_dialog demo')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'This demo opens Plugin Kit Dialog against a runtime with '
                    '20 competing plugins (priority towers, locked + experimental '
                    'tiers) plus a PluginKitVisualsPlugin, and shows the latest '
                    'settings returned by Save.',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.center,
                    child: ElevatedButton.icon(
                      onPressed: _openDialog,
                      icon: const Icon(Icons.tune),
                      label: const Text('Open Plugin Kit Dialog'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _settingsPreview,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
