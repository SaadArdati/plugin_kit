import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  test('TextConfigField keeps its values', () {
    const f = TextConfigField(
      key: 'name',
      label: 'Name',
      placeholder: 'Type…',
      defaultValue: 'foo',
    );
    expect(f.key, 'name');
    expect(f.label, 'Name');
    expect(f.placeholder, 'Type…');
    expect(f.defaultValue, 'foo');
  });

  test('MultilineConfigField defaults: minLines=6, maxLines=14, no tags', () {
    const f = MultilineConfigField(key: 'prompt', label: 'Prompt');
    expect(f.minLines, 6);
    expect(f.maxLines, 14);
    expect(f.moustacheTags, isEmpty);
  });

  test(
    'NumberConfigField with min+max signals slider mode (caller checks)',
    () {
      const f = NumberConfigField(
        key: 't',
        label: 'Temperature',
        min: 0,
        max: 2,
        step: 0.1,
      );
      expect(f.min, 0);
      expect(f.max, 2);
      expect(f.step, 0.1);
    },
  );

  test('DropdownConfigField is generic over T', () {
    const f = DropdownConfigField<String>(
      key: 'p',
      label: 'Provider',
      options: [DropdownOption('a', 'A'), DropdownOption('b', 'B')],
    );
    expect(f.options, hasLength(2));
    expect(f.options.first.value, 'a');
  });

  test('GroupConfigField nests children', () {
    const f = GroupConfigField(
      key: 'g',
      label: 'Group',
      children: [
        TextConfigField(key: 'a', label: 'A'),
        BoolConfigField(key: 'b', label: 'B'),
      ],
    );
    expect(f.children, hasLength(2));
  });

  test('ConfigField switch is exhaustive', () {
    const ConfigField f = TextConfigField(key: 'k', label: 'L');
    final result = switch (f) {
      TextConfigField() => 'text',
      MultilineConfigField() => 'multiline',
      PasswordConfigField() => 'password',
      NumberConfigField() => 'number',
      DropdownConfigField() => 'dropdown',
      BoolConfigField() => 'bool',
      GroupConfigField() => 'group',
      ExtensionConfigField() => 'extension',
    };
    expect(result, 'text');
  });

  test('ExtensionConfigField carries renderer key and opaque args', () {
    const f = ExtensionConfigField(
      key: 'theme.accent',
      label: 'Accent',
      rendererKey: 'color_picker',
      args: {'allow_alpha': false},
    );
    expect(f.rendererKey, 'color_picker');
    expect(f.args['allow_alpha'], false);
  });
}
