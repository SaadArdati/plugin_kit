import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/services/service_card.dart';
import 'package:plugin_kit_dialog_demo/plugin_visuals.dart';
import 'package:plugin_kit_dialog_demo/plugins/all.dart';

/// Pumps a full [PluginKitDialog] over a transparent background so the
/// captured PNG has no opaque scaffold around the dialog. The dialog itself
/// supplies its own surface; everything outside that surface stays empty.
Future<void> _pumpDialog(
  WidgetTester tester, {
  required PluginRuntime runtime,
  required PluginKitDialogController controller,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildPluginKitDialogDarkTheme().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: PluginKitDialog(
            controller: controller,
            onSave: (_) async {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PluginKitDialogController _buildController(PluginRuntime runtime) {
  return PluginKitDialogController(
    runtime: runtime,
    initialSettings: RuntimeSettings.empty(),
  );
}

PluginRuntime _buildRuntime() {
  final runtime = PluginRuntime();
  runtime.addPlugins(demoPlugins());
  runtime.addPlugin(visualsPlugin());
  runtime.init(settings: RuntimeSettings.empty());
  return runtime;
}

void main() {
  setUpAll(() async {
    // Load real fonts (Roboto, Material Icons, etc.) so goldens render with
    // actual glyphs instead of the Ahem block-text fallback. Otherwise these
    // PNGs are useful only for layout regression, not as doc images.
    await loadAppFonts();
  });

  setUp(() {
    // Tests tap elements with real hit testing; ensure the fixed viewport has
    // enough headroom for the dialog's max-height constraint.
  });

  testWidgets('plugins_tab_dark matches golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final runtime = _buildRuntime();
    addTearDown(runtime.dispose);
    final controller = _buildController(runtime);

    await _pumpDialog(tester, runtime: runtime, controller: controller);

    await expectLater(
      find.byType(PluginKitDialog),
      matchesGoldenFile('goldens/plugins_tab_dark.png'),
    );
  });

  testWidgets('services_tab_dark matches golden (chat_manager expanded)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final runtime = _buildRuntime();
    addTearDown(runtime.dispose);
    final controller = _buildController(runtime);
    controller.showAllServices = true;

    await _pumpDialog(tester, runtime: runtime, controller: controller);

    // Switch to Services tab.
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    // Expand the second visible card (index 1) in the fixed viewport.
    final cards = find.byType(ServiceCard);
    expect(cards, findsAtLeastNWidgets(2));
    await tester.tap(cards.at(1));
    await tester.pumpAndSettle();

    // Verify expanded state is reachable before snapping the golden.
    expect(find.text('enterprise_chat'), findsOneWidget);
    expect(find.text('Priority 120'), findsOneWidget);

    await expectLater(
      find.byType(PluginKitDialog),
      matchesGoldenFile('goldens/services_tab_dark.png'),
    );
  });

  testWidgets('advanced_tab_dark matches golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final runtime = _buildRuntime();
    addTearDown(runtime.dispose);
    final controller = _buildController(runtime);

    await _pumpDialog(tester, runtime: runtime, controller: controller);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PluginKitDialog),
      matchesGoldenFile('goldens/advanced_tab_dark.png'),
    );
  });
}
