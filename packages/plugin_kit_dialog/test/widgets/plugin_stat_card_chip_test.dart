import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/plugins/plugin_card.dart';
import 'package:plugin_kit_dialog/src/widgets/plugins/plugin_stat_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('PluginStatCard shows numerator/denominator and label', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PluginStatCard(
          icon: Icons.extension,
          iconBackground: Colors.blue,
          numerator: 18,
          denominator: 27,
          label: 'Active Plugins',
        ),
      ),
    );
    expect(find.text('18 / 27'), findsOneWidget);
    expect(find.text('Active Plugins'), findsOneWidget);
  });

  testWidgets('PluginChip toggles via callback when not locked', (
    tester,
  ) async {
    bool? captured;
    await tester.pumpWidget(
      _wrap(
        PluginCard(
          label: 'foo',
          enabled: false,
          locked: false,
          onChanged: (v) => captured = v,
        ),
      ),
    );
    await tester.tap(find.byType(PluginCard));
    expect(captured, isTrue);
  });

  testWidgets('PluginChip with locked=true ignores taps and shows padlock', (
    tester,
  ) async {
    bool called = false;
    await tester.pumpWidget(
      _wrap(
        PluginCard(
          label: 'core',
          enabled: true,
          locked: true,
          onChanged: (_) => called = true,
        ),
      ),
    );
    await tester.tap(find.byType(PluginCard), warnIfMissed: false);
    expect(called, isFalse);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    // Locked replaces the checkbox: neither checkbox glyph should appear.
    expect(find.byIcon(Icons.check_box_rounded), findsNothing);
    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsNothing);
  });
}
