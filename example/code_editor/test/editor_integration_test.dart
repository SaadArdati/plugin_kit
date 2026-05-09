import 'package:code_editor/app/editor_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integration tests for the Code Editor Flutter capstone.
///
/// Tests exercise the plugin-contributed UI: toolbar buttons, panels,
/// plugin toggling via chips, tab switching, and document content.
void main() {
  group('Editor boots and renders', () {
    testWidgets('shows chip bar with plugin toggles', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      expect(find.text('Plugins'), findsOneWidget);
      expect(find.text('Runner'), findsWidgets);
      expect(find.text('Git'), findsWidgets);
      expect(find.text('Terminal'), findsWidgets);
      expect(find.text('AI Assist'), findsWidgets);
      expect(find.text('Minimap'), findsWidgets);
    });

    testWidgets('shows two document tabs', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      expect(find.text('query.sql'), findsWidgets);
      expect(find.text('main.dart'), findsWidgets);
    });

    testWidgets('shows plugin-contributed toolbar buttons', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      // Runner contributes a Run button
      expect(find.text('Run'), findsOneWidget);
      // Git contributes a branch badge
      expect(find.text('main'), findsWidgets);
      // AI contributes an AI button
      expect(find.text('AI'), findsWidgets);
    });

    testWidgets('loads SQL document content', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      final controller = (tester.widget<TextField>(textField)).controller!;
      expect(controller.text, contains('select'));
      expect(controller.text, contains('from users'));
    });

    testWidgets('shows bottom panel with Console tab', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      expect(find.text('Console'), findsWidgets);
    });

    testWidgets('shows status bar', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      expect(find.text('SQL'), findsWidgets);
      expect(find.text('plugin_kit'), findsOneWidget);
    });
  });

  group('Tab switching', () {
    testWidgets('switching to main.dart shows Dart content', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('main.dart'));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      final controller = (tester.widget<TextField>(textField)).controller!;
      expect(controller.text, contains('class MyApp'));
      expect(controller.text, contains('TODO'));
    });

    testWidgets('switching back preserves edited content', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'select 42');
      await tester.pumpAndSettle();

      await tester.tap(find.text('main.dart'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('query.sql'));
      await tester.pumpAndSettle();

      final controller = (tester.widget<TextField>(textField)).controller!;
      expect(controller.text, equals('select 42'));
    });
  });

  group('Plugin toggling', () {
    testWidgets('disabling Runner removes Run button', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      expect(find.text('Run'), findsOneWidget);

      // Tap Runner chip to disable
      final runnerChip = find.text('Runner').first;
      await tester.tap(runnerChip);
      await tester.pumpAndSettle();

      expect(find.text('Run'), findsNothing);
    });

    testWidgets('disabling Git removes branch button', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      // Precondition: Git contributes a "main" branch toolbar action.
      expect(find.text('main'), findsWidgets);

      // Disable Git.
      final gitChip = find.text('Git').first;
      await tester.tap(gitChip);
      await tester.pumpAndSettle();

      // The "main" toolbar button must be gone. The Git panel may also
      // still show "main" elsewhere if the chip doesn't re-collect, so we
      // scope the assertion to the toolbar specifically: the toolbar action
      // plugin_id that read 'main' will no longer be emitted when Git is
      // disabled, and there are no other toolbar contributions that say
      // 'main'.
      expect(find.text('main'), findsNothing);
    });

    testWidgets('re-enabling Runner restores Run button', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      // Disable
      final runnerChip = find.text('Runner').first;
      await tester.tap(runnerChip);
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsNothing);

      // Re-enable
      await tester.tap(find.text('Runner').first);
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsOneWidget);
    });
  });

  group('Panel toggling', () {
    testWidgets('AI button toggles AI Assist panel', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      // AI panel should not be open initially
      expect(find.text('AI Assistant'), findsNothing);

      // Tap AI toolbar button
      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // AI panel should now be visible
      expect(find.text('AI Assistant'), findsOneWidget);
    });

    testWidgets('bottom panel collapses and expands', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      // The bottom panel must expose a collapse arrow. If it doesn't, the
      // shell has regressed and the test should fail: not silently skip.
      final collapseArrow = find.byIcon(Icons.keyboard_arrow_down);
      expect(collapseArrow, findsOneWidget);

      await tester.tap(collapseArrow);
      await tester.pumpAndSettle();

      // Collapsing hides the Console placeholder.
      expect(find.text('Press Run to start'), findsNothing);

      final expandArrow = find.byIcon(Icons.keyboard_arrow_up);
      expect(expandArrow, findsOneWidget);
      await tester.tap(expandArrow);
      await tester.pumpAndSettle();

      expect(find.text('Press Run to start'), findsOneWidget);
    });
  });

  group('UIRefreshRequest wiring', () {
    testWidgets('pressing Run causes the status bar to re-collect', (
      tester,
    ) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      // Initial state: "Running..." status item not visible.
      expect(find.text('Running...'), findsNothing);

      // Pressing Run flips the runner's internal state and emits
      // UIRefreshRequest. The shell must re-collect status bar items,
      // which now include "Running..." from the runner plugin.
      await tester.tap(find.text('Run'));
      // The runner's handler is async: tap → emit ToolbarActionTriggered →
      // Runner.on → _startRun → emit UIRefreshRequest → shell → _collectUI.
      // Pump a few frames to let the chain complete before asserting.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final statusBar = find.byKey(const Key('editor-status-bar'));
      expect(statusBar, findsOneWidget);
      expect(
        find.descendant(of: statusBar, matching: find.text('Running...')),
        findsOneWidget,
      );
    });
  });

  group('Plugin toggle stability', () {
    testWidgets('rapid off-then-on toggle ends in the on state', (
      tester,
    ) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      expect(find.text('Run'), findsOneWidget);

      // Disable Runner, then re-enable before the first reconcile finishes.
      // `updateSessionSettings` is async: without serialization in the
      // shell, the second toggle captures `old` against the pre-disable
      // session state and silently drops the re-enable.
      final runnerChip = find.text('Runner').first;
      await tester.tap(runnerChip);
      // Rebuild so the chip's `selected=false` is reflected; no
      // pumpAndSettle: we want the reconcile still in flight.
      await tester.pump();
      await tester.tap(find.text('Runner').first);
      await tester.pumpAndSettle();

      // Both reconciliations landed; Runner must be enabled again.
      expect(find.text('Run'), findsOneWidget);
    });
  });

  group('Document editing', () {
    testWidgets('editing text preserves through tab switch', (tester) async {
      await tester.pumpWidget(const EditorApp());
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'select 1 from dual');
      await tester.pumpAndSettle();

      // Switch away and back
      await tester.tap(find.text('main.dart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('query.sql'));
      await tester.pumpAndSettle();

      final controller = (tester.widget<TextField>(textField)).controller!;
      expect(controller.text, contains('select 1 from dual'));
    });
  });
}
