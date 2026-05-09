import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/password_field_input.dart';
import 'package:plugin_kit_dialog/src/widgets/services/fields/text_field_input.dart';

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
  testWidgets('TextFieldInput writes typed value to handle (after debounce)', (
    tester,
  ) async {
    final handle = _Handle();
    await tester.pumpWidget(
      _wrap(
        TextFieldInput(
          field: const TextConfigField(key: 'name', label: 'Name'),
          handle: handle,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump(const Duration(milliseconds: 250));
    expect(handle.value, 'hello');
  });

  testWidgets(
    'PasswordFieldInput obscures by default and toggles on icon tap',
    (tester) async {
      final handle = _Handle();
      await tester.pumpWidget(
        _wrap(
          PasswordFieldInput(
            field: const PasswordConfigField(key: 'k', label: 'API Key'),
            handle: handle,
          ),
        ),
      );
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump();
      final field2 = tester.widget<TextField>(find.byType(TextField));
      expect(field2.obscureText, isFalse);
    },
  );
}
