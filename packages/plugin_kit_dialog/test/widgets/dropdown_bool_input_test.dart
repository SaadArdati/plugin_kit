import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/bool_field_input.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/dropdown_field_input.dart';

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
  testWidgets(
    'DropdownFieldInput shows all options and writes selected value',
    (tester) async {
      final handle = _Handle();
      await tester.pumpWidget(
        _wrap(
          DropdownFieldInput<String>(
            field: const DropdownConfigField<String>(
              key: 'p',
              label: 'Provider',
              options: [DropdownOption('a', 'A'), DropdownOption('b', 'B')],
            ),
            handle: handle,
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B').last);
      await tester.pumpAndSettle();
      expect(handle.value, 'b');
    },
  );

  testWidgets('BoolFieldInput toggles via Switch', (tester) async {
    final handle = _Handle();
    await tester.pumpWidget(
      _wrap(
        BoolFieldInput(
          field: const BoolConfigField(key: 'b', label: 'B'),
          handle: handle,
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(handle.value, isTrue);
  });
}
