import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog_demo/main.dart';
import 'package:plugin_kit_dialog_demo/plugin_visuals.dart';
import 'package:plugin_kit_dialog_demo/plugins/all.dart';

class _DialogResultHarness extends StatefulWidget {
  const _DialogResultHarness({required this.onReturned});

  final ValueChanged<RuntimeSettings?> onReturned;

  @override
  State<_DialogResultHarness> createState() => _DialogResultHarnessState();
}

class _DialogResultHarnessState extends State<_DialogResultHarness> {
  late final PluginRuntime _runtime;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  RuntimeSettings _settings = RuntimeSettings();

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
    final BuildContext? dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null) {
      return;
    }
    final RuntimeSettings? next = await showPluginKitDialog(
      context: dialogContext,
      runtime: _runtime,
      initialSettings: _settings,
      onSave: (_) async {},
    );
    widget.onReturned(next);
    if (next != null && mounted) {
      setState(() {
        _settings = next;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: _openDialog,
            child: const Text('Open Plugin Kit Dialog'),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('demo app boots and opens the dialog', (tester) async {
    await tester.pumpWidget(const PluginKitDialogDemoApp());
    await tester.pumpAndSettle();
    expect(find.text('Open Plugin Kit Dialog'), findsOneWidget);

    await tester.tap(find.text('Open Plugin Kit Dialog'));
    await tester.pumpAndSettle();

    // All three tabs visible.
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);

    // Save is disabled when not dirty: verify via the widget.
    final saveBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveBtn.onPressed, isNull);
  });

  testWidgets('dialog cancels cleanly and returns null', (tester) async {
    RuntimeSettings? returned = RuntimeSettings();
    await tester.pumpWidget(
      _DialogResultHarness(
        onReturned: (RuntimeSettings? value) {
          returned = value;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Plugin Kit Dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    // Back to the demo home screen.
    expect(find.text('Open Plugin Kit Dialog'), findsOneWidget);
  });
}
