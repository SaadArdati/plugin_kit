// Golden tests. Tagged `goldens` so CI can skip them with
// `flutter test --exclude-tags=goldens`. Run locally to regenerate doc
// images: `flutter test --update-goldens test/golden_test.dart`.
@Tags(['goldens'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:code_editor/app/editor_app.dart';
import 'package:golden_toolkit/golden_toolkit.dart';

/// Pumps small frames until [finder] matches at least one widget, or until
/// the timeout elapses. Replaces arbitrary `pump(500ms)` waits for async
/// plugin init: we actually know what we're waiting for (the initial
/// toolbar actions to appear), so we should wait for exactly that.
Future<void> _pumpUntilPresent(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
  Duration step = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(step);
  }
  throw TestFailure(
    'Timed out waiting ${timeout.inMilliseconds}ms for $finder to match.',
  );
}

/// Boots the editor and waits until the shell has finished its initial
/// async init (session created, plugins registered, UI collected). The
/// "Run" toolbar button appearing is a reliable readiness signal because
/// it requires the RunnerPlugin to have registered and `_collectUI` to
/// have completed at least once.
Future<void> _bootAndSettle(WidgetTester tester) async {
  await tester.pumpWidget(const EditorApp());
  await tester.pumpAndSettle();
  await _pumpUntilPresent(tester, find.text('Run'));
  await tester.pumpAndSettle();
}

void _configureGoldenEnvironment(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
  tester.platformDispatcher.textScaleFactorTestValue = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAllTestValues();
  });
}

/// Golden tests that capture the editor UI in various states.
/// Run with: flutter test --update-goldens test/golden_test.dart
/// Then view the PNGs in test/goldens/
void main() {
  const testSize = Size(1280, 800);

  setUpAll(() async {
    await loadAppFonts();
  });

  testWidgets('golden: initial state with SQL tab', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/01_initial_sql.png'),
    );
  });

  testWidgets('golden: Dart tab selected', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    // Switch to Dart tab
    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/02_dart_tab.png'),
    );
  });

  testWidgets('golden: Git panel open', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    // Click git branch button to open Changes panel
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/03_git_panel.png'),
    );
  });

  testWidgets('golden: AI panel open', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    // Click AI button to open AI Assist panel
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/04_ai_panel.png'),
    );
  });

  testWidgets('golden: bottom panel collapsed', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    // Find and tap the collapse arrow
    final arrow = find.byIcon(Icons.keyboard_arrow_down);
    expect(arrow, findsOneWidget);
    await tester.tap(arrow);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/05_bottom_collapsed.png'),
    );
  });

  testWidgets('golden: some plugins disabled', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    // Disable Runner chip
    final runnerChip = find.text('Runner');
    await tester.tap(runnerChip);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Disable Git chip
    final gitChip = find.text('Git');
    await tester.tap(gitChip);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // Disable Minimap chip
    final minimapChip = find.text('Minimap');
    await tester.tap(minimapChip);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/06_plugins_disabled.png'),
    );
  });

  testWidgets('golden: terminal tab active', (tester) async {
    _configureGoldenEnvironment(tester, testSize);

    await _bootAndSettle(tester);

    // Click Terminal tab in the bottom panel (find the tab, not the chip)
    final terminalTab = find.text('Terminal').last;
    await tester.tap(terminalTab);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/07_terminal_tab.png'),
    );
  });

  testWidgets('golden: both side panels open', (tester) async {
    _configureGoldenEnvironment(tester, const Size(1440, 900));

    await _bootAndSettle(tester);

    // Open Git panel
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // Open AI panel
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(EditorApp),
      matchesGoldenFile('goldens/08_both_side_panels.png'),
    );
  });
}
