import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

class _StubPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('sample_plugin');
}

void main() {
  testWidgets('PluginKitDialogBody renders the header and active tab body', (
    tester,
  ) async {
    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    await tester.pumpWidget(
      _app(
        PluginKitDialogBody(
          controller: controller,
          runtime: runtime,
          onSave: (_) async {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('Plugins'), findsOneWidget);
    expect(find.text('Active Plugins'), findsOneWidget);
    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('Switching tabs changes the visible tab body', (tester) async {
    // The dialog needs a realistic viewport; the default 800x600 clips the
    // header's single row with tabs + actions.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    await tester.pumpWidget(
      _app(
        PluginKitDialogBody(
          controller: controller,
          runtime: runtime,
          onSave: (_) async {},
          onCancel: () {},
        ),
      ),
    );

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(find.text('Service Registry'), findsOneWidget);
  });

  testWidgets(
    'showPluginKitDialog resolves with null when user cancels clean',
    (tester) async {
      late BuildContext capturedContext;
      final runtime = PluginRuntime();
      runtime.init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      RuntimeSettings? onSaveReceived;
      final futureResult = showPluginKitDialog(
        context: capturedContext,
        runtime: runtime,
        initialSettings: RuntimeSettings(),
        onSave: (settings) async => onSaveReceived = settings,
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      final result = await futureResult;
      expect(result, isNull);
      expect(onSaveReceived, isNull);
    },
  );

  testWidgets('showPluginKitDialog resolves with saved settings after Save', (
    tester,
  ) async {
    late BuildContext capturedContext;
    final runtime = PluginRuntime()..addPlugin(_StubPlugin());
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    RuntimeSettings? onSaveReceived;
    final futureResult = showPluginKitDialog(
      context: capturedContext,
      runtime: runtime,
      initialSettings: RuntimeSettings(),
      onSave: (settings) async => onSaveReceived = settings,
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('sample_plugin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final result = await futureResult;
    expect(result, isNotNull);
    expect(result, equals(onSaveReceived));
    expect(result!.plugins[const PluginId('sample_plugin')]?.enabled, isFalse);
  });

  testWidgets(
    'showPluginKitDialog locks the UI and shows a spinner while onSave is in '
    'flight; system back is suppressed during save',
    (tester) async {
      late BuildContext capturedContext;
      final runtime = PluginRuntime()..addPlugin(_StubPlugin());
      runtime.init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final saveCompleter = Completer<void>();
      final futureResult = showPluginKitDialog(
        context: capturedContext,
        runtime: runtime,
        initialSettings: RuntimeSettings(),
        onSave: (_) => saveCompleter.future,
      );

      await tester.pumpAndSettle();
      // Dirty the draft so Save is enabled.
      await tester.tap(find.text('sample_plugin'));
      await tester.pumpAndSettle();

      // Trigger save; onSave is awaiting the completer, so the dialog stays
      // in the "saving" state until we complete it below.
      await tester.tap(find.text('Save'));
      await tester.pump();

      // Save button label flips to "Saving…" and shows the inline spinner.
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Save'), findsNothing);

      // System back during save is suppressed entirely.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.text('Saving…'),
        findsOneWidget,
        reason: 'dialog should still be up after back press during save',
      );

      // Now let onSave resolve: dialog closes with the saved settings.
      saveCompleter.complete();
      await tester.pumpAndSettle();

      final result = await futureResult;
      expect(result, isNotNull);
      expect(
        result!.plugins[const PluginId('sample_plugin')]?.enabled,
        isFalse,
      );
    },
  );

  testWidgets('showPluginKitDialog treats system back as cancel', (
    tester,
  ) async {
    late BuildContext capturedContext;
    final runtime = PluginRuntime();
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final futureResult = showPluginKitDialog(
      context: capturedContext,
      runtime: runtime,
      initialSettings: RuntimeSettings(),
      onSave: (_) async {},
    );

    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final result = await futureResult;
    expect(result, isNull);
  });
}
