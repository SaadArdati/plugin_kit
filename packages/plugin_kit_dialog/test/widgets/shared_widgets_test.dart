import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/shared/plugin_kit_dialog_card.dart';
import 'package:plugin_kit_dialog/src/widgets/shared/reset_button.dart';
import 'package:plugin_kit_dialog/src/widgets/shared/section_header.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('PluginKitDialogCard renders header + child', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PluginKitDialogCard(header: Text('Title'), child: Text('Body')),
      ),
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('SectionHeader renders icon, title, optional subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SectionHeader(
          icon: Icons.shield,
          iconBackground: Colors.green,
          title: 'Stable Plugins',
          subtitle: 'Production-ready plugins',
        ),
      ),
    );
    expect(find.text('Stable Plugins'), findsOneWidget);
    expect(find.text('Production-ready plugins'), findsOneWidget);
    expect(find.byIcon(Icons.shield), findsOneWidget);
  });

  testWidgets('ResetButton becomes inert when not overridden', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(ResetButton(isOverridden: false, onReset: () => calls++)),
    );
    await tester.tap(find.byType(IconButton), warnIfMissed: false);
    expect(calls, 0);
  });

  testWidgets('ResetButton fires when overridden', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _wrap(ResetButton(isOverridden: true, onReset: () => calls++)),
    );
    await tester.tap(find.byType(IconButton));
    expect(calls, 1);
  });
}
