// ignore_for_file: unnecessary_cast

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

void main() {
  test('PluginKitDialogTheme.dark() ships the screenshot palette', () {
    final theme = PluginKitDialogTheme.dark();
    expect(theme.stableAccent, const Color(0xFF22C55E)); // green
    expect(theme.experimentalAccent, const Color(0xFFF59E0B)); // orange
    expect(theme.agentAccent, const Color(0xFFA855F7)); // purple
  });

  test('copyWith only overrides supplied fields', () {
    final base = PluginKitDialogTheme.dark();
    final next = base.copyWith(stableAccent: const Color(0xFF000000));
    expect(next.stableAccent, const Color(0xFF000000));
    expect(next.experimentalAccent, base.experimentalAccent);
  });

  test('lerp interpolates colors at t=0.5', () {
    final a = PluginKitDialogTheme.dark();
    final b = PluginKitDialogTheme.light();
    final mid = a.lerp(b, 0.5) as PluginKitDialogTheme;
    final expected = Color.lerp(a.stableAccent, b.stableAccent, 0.5)!;
    expect(mid.stableAccent, expected);
  });

  testWidgets(
    'PluginKitDialogTheme.of falls back to dark when extension absent and brightness dark',
    (tester) async {
      PluginKitDialogTheme? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (ctx) {
              captured = PluginKitDialogTheme.of(ctx);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured, isNotNull);
      expect(captured!.stableAccent, PluginKitDialogTheme.dark().stableAccent);
    },
  );

  testWidgets(
    'PluginKitDialogTheme.of falls back to light when extension absent and brightness light',
    (tester) async {
      PluginKitDialogTheme? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (ctx) {
              captured = PluginKitDialogTheme.of(ctx);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(captured, isNotNull);
      expect(captured!.stableAccent, PluginKitDialogTheme.light().stableAccent);
    },
  );

  test('buildPluginKitDialogDarkTheme registers the extension', () {
    final data = buildPluginKitDialogDarkTheme();
    expect(data.brightness, Brightness.dark);
    expect(data.extension<PluginKitDialogTheme>(), isNotNull);
  });

  test('buildPluginKitDialogLightTheme registers the extension', () {
    final data = buildPluginKitDialogLightTheme();
    expect(data.brightness, Brightness.light);
    expect(data.extension<PluginKitDialogTheme>(), isNotNull);
  });
}
