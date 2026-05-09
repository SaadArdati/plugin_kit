import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/multiline_field_input.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/number_field_input.dart';

class _Handle implements ConfigFieldHandle {
  Object? _v;

  @override
  Object? get value => _v;

  @override
  set value(Object? v) => _v = v;

  @override
  bool get isOverridden => _v != null;

  @override
  void reset() => _v = null;
}

Widget _wrap(Widget child) => MaterialApp(
  theme: buildPluginKitDialogDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('MultilineFieldInput shows moustache chips when tags supplied', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        MultilineFieldInput(
          field: const MultilineConfigField(
            key: 'k',
            label: 'L',
            moustacheTags: ['foo', 'bar'],
          ),
          handle: _Handle(),
        ),
      ),
    );
    expect(find.text('Available moustache tags'), findsOneWidget);
    expect(find.text('foo'), findsOneWidget);
    expect(find.text('bar'), findsOneWidget);
  });

  testWidgets('NumberFieldInput renders slider when min and max set', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        NumberFieldInput(
          field: const NumberConfigField(
            key: 't',
            label: 'T',
            min: 0,
            max: 2,
            step: 0.1,
          ),
          handle: _Handle(),
        ),
      ),
    );
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('NumberFieldInput renders text input when min OR max missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        NumberFieldInput(
          field: const NumberConfigField(key: 'n', label: 'N'),
          handle: _Handle(),
        ),
      ),
    );
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });
}
