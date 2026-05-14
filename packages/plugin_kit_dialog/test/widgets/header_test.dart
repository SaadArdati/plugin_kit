import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/events.dart';
import 'package:plugin_kit_dialog/src/widgets/header/plugin_kit_dialog_header.dart';
import 'package:plugin_kit_dialog/src/widgets/header/unsaved_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

PluginKitDialogController _ctrl() {
  final runtime = PluginRuntime();
  runtime.init(settings: RuntimeSettings());
  return PluginKitDialogController(
    runtime: runtime,
    initialSettings: RuntimeSettings(),
  );
}

List<TabDescriptor> _tabs() => [
  TabDescriptor(
    id: 'plugins',
    label: 'Plugins',
    icon: const Icon(Icons.extension),
    order: 100,
    builder: (_) => const SizedBox(),
  ),
  TabDescriptor(
    id: 'services',
    label: 'Services',
    icon: const Icon(Icons.settings),
    order: 200,
    builder: (_) => const SizedBox(),
  ),
  TabDescriptor(
    id: 'advanced',
    label: 'Advanced',
    icon: const Icon(Icons.code),
    order: 300,
    builder: (_) => const SizedBox(),
  ),
];

void main() {
  testWidgets('UnsavedBadge is invisible when controller is not dirty', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(
        ListenableBuilder(
          listenable: controller,
          builder: (_, _) => UnsavedBadge(visible: controller.isDirty),
        ),
      ),
    );
    expect(find.text('Unsaved'), findsNothing);
  });

  testWidgets('UnsavedBadge appears when controller becomes dirty', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(
        ListenableBuilder(
          listenable: controller,
          builder: (_, _) => UnsavedBadge(visible: controller.isDirty),
        ),
      ),
    );
    controller.setPluginEnabled(const PluginId('x'), true);
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);
  });

  testWidgets('header renders three tab pills + Refresh/Cancel/Save', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(
        PluginKitDialogHeader(
          controller: controller,
          tabs: _tabs(),
          activeTabId: 'plugins',
          onTabSelected: (_) {},
          onCancel: () {},
          onSave: () async {},
        ),
      ),
    );
    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Refresh button calls controller.resetAll', (tester) async {
    final controller = _ctrl();
    controller.setPluginEnabled(const PluginId('x'), true);
    await tester.pumpWidget(
      _wrap(
        PluginKitDialogHeader(
          controller: controller,
          tabs: _tabs(),
          activeTabId: 'plugins',
          onTabSelected: (_) {},
          onCancel: () {},
          onSave: () async {},
        ),
      ),
    );
    expect(controller.isDirty, isTrue);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(controller.isDirty, isFalse);
  });

  testWidgets('Save button is disabled when not dirty', (tester) async {
    final controller = _ctrl();
    var savedCalled = false;
    await tester.pumpWidget(
      _wrap(
        PluginKitDialogHeader(
          controller: controller,
          tabs: _tabs(),
          activeTabId: 'plugins',
          onTabSelected: (_) {},
          onCancel: () {},
          onSave: () async => savedCalled = true,
        ),
      ),
    );

    final saveButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(saveButton.onPressed, isNull);
    expect(savedCalled, isFalse);
  });
}
