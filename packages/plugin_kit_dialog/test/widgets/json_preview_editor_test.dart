import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/advanced/json_preview_editor.dart';

Widget _wrap(PluginKitDialogController controller, Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

PluginKitDialogController _ctrl() {
  final runtime = PluginRuntime()..init(settings: RuntimeSettings.empty());
  addTearDown(runtime.dispose);
  return PluginKitDialogController(
    runtime: runtime,
    initialSettings: RuntimeSettings.empty(),
  );
}

void main() {
  testWidgets('initial text reflects encoded working settings', (tester) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('"plugins"'));
    expect(field.controller!.text, contains('"services"'));
  });

  testWidgets('typing in editor, before debounce, leaves draft untouched', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    await tester.enterText(
      find.byType(TextField),
      '{"plugins":{},"services":{}}',
    );

    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.draft.working, RuntimeSettings.empty());
  });

  testWidgets('debounce fires on valid JSON and updates controller draft', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    await tester.enterText(
      find.byType(TextField),
      '{"plugins":{"foo":{"enabled":true,"config":{}}},"services":{}}',
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      controller.draft.working.plugins[const PluginId('foo')]?.enabled,
      isTrue,
    );
  });

  testWidgets(
    'invalid JSON surfaces an error banner and keeps draft untouched',
    (tester) async {
      final controller = _ctrl();
      await tester.pumpWidget(
        _wrap(controller, JsonPreviewEditor(controller: controller)),
      );

      await tester.enterText(find.byType(TextField), '{not json');
      await tester.pump(const Duration(milliseconds: 350));

      expect(controller.draft.working, RuntimeSettings.empty());
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    },
  );

  testWidgets('shape mismatch is treated as parse error and keeps draft', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    await tester.enterText(
      find.byType(TextField),
      '{"plugins":{},"services":{},"unexpected":true}',
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(controller.draft.working, RuntimeSettings.empty());
    expect(find.textContaining('Settings shape mismatch'), findsOneWidget);
  });

  testWidgets('gaining focus is a no-op for editor text', (tester) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    final before = tester.widget<TextField>(find.byType(TextField));
    final beforeText = before.controller!.text;

    await tester.tap(find.byType(TextField));
    await tester.pump();

    final after = tester.widget<TextField>(find.byType(TextField));
    expect(after.controller!.text, beforeText);
  });

  testWidgets(
    'losing focus with parse error snaps back to last known-good JSON',
    (tester) async {
      final controller = _ctrl();
      await tester.pumpWidget(
        _wrap(controller, JsonPreviewEditor(controller: controller)),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '{broken');
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      final expected = const JsonEncoder.withIndent(
        '  ',
      ).convert(controller.draft.working.toJson());
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, expected);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    },
  );

  testWidgets('controller mutation with editor unfocused re-encodes text', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    controller.setPluginEnabled(const PluginId('bar'), true);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('"bar"'));
  });

  testWidgets('controller mutation while focused does not stomp user text', (
    tester,
  ) async {
    final controller = _ctrl();
    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'WORK IN PROGRESS');

    controller.setPluginEnabled(const PluginId('bar'), true);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'WORK IN PROGRESS');
  });

  testWidgets(
    'showAllServices keeps editable JSON minimal and shows read-only expansion',
    (tester) async {
      final runtime = PluginRuntime()..addPlugin(_JsonPreviewPlugin());
      runtime.init(settings: RuntimeSettings.empty());
      addTearDown(runtime.dispose);

      final controller = PluginKitDialogController(
        runtime: runtime,
        initialSettings: RuntimeSettings.empty(),
      );

      await tester.pumpWidget(
        _wrap(controller, JsonPreviewEditor(controller: controller)),
      );

      final initialField = tester.widget<TextField>(find.byType(TextField));
      expect(
        jsonDecode(initialField.controller!.text),
        equals({
          'plugins': <String, dynamic>{},
          'services': <String, dynamic>{},
        }),
      );

      controller.showAllServices = true;
      await tester.pump();

      final expandedField = tester.widget<TextField>(find.byType(TextField));
      expect(
        jsonDecode(expandedField.controller!.text),
        equals({
          'plugins': <String, dynamic>{},
          'services': <String, dynamic>{},
        }),
      );
      expect(find.text('Expanded (read-only)'), findsOneWidget);
      expect(find.textContaining('json_preview_plugin'), findsOneWidget);
      expect(
        find.textContaining('json_preview_plugin:main_agent.agent_service'),
        findsOneWidget,
      );

      controller.showAllServices = false;
      await tester.pump();

      final collapsedField = tester.widget<TextField>(find.byType(TextField));
      expect(
        jsonDecode(collapsedField.controller!.text),
        equals({
          'plugins': <String, dynamic>{},
          'services': <String, dynamic>{},
        }),
      );
      expect(find.text('Expanded (read-only)'), findsNothing);
    },
  );

  testWidgets('toggling show-all then typing does not dirty the draft', (
    tester,
  ) async {
    final runtime = PluginRuntime()..addPlugin(_JsonPreviewPlugin());
    runtime.init(settings: RuntimeSettings.empty());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings.empty(),
    );

    await tester.pumpWidget(
      _wrap(controller, JsonPreviewEditor(controller: controller)),
    );

    controller.showAllServices = true;
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    await tester.enterText(
      find.byType(TextField),
      '${field.controller!.text} ',
    );
    await tester.pump(const Duration(milliseconds: 350));

    controller.showAllServices = false;
    await tester.pump();

    expect(controller.draft.working, RuntimeSettings.empty());
    expect(controller.isDirty, isFalse);
  });
}

class _JsonPreviewPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('json_preview_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      ServiceId.namespaced(Namespace('main_agent'), 'agent_service'),
      Object(),
    );
  }
}
