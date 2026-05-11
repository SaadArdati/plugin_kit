/// Declarative schema for fields rendered by the configuration dialog.
///
/// Lives in `plugin_kit` (Dart-only) so plugins authored in non-Flutter
/// packages can declare their configuration surface without taking a Flutter
/// dependency. The actual rendering happens in `plugin_kit_dialog` (Flutter).
library;

/// Base schema for a configurable input rendered by the dialog.
// #docregion config-field-config-field
sealed class ConfigField {
  /// Dotted-key path under `ServiceSettings.config`.
  /// Examples: `"model"`, `"provider.name"`, `"limits.max_tokens"`.
  final String key;

  /// Human-readable label shown above the input.
  final String label;

  /// Optional helper text rendered below the input in muted style.
  final String? helperText;

  /// Default value used by the "reset" button. May be null.
  final Object? defaultValue;

  /// Creates a config field schema entry.
  const ConfigField({
    required this.key,
    required this.label,
    this.helperText,
    this.defaultValue,
  });
}
// #enddocregion config-field-config-field

/// Single-line text input.
// #docregion config-field-text-config-field
final class TextConfigField extends ConfigField {
  /// Placeholder text shown when no value is set.
  final String? placeholder;

  /// Creates a single-line text field schema.
  const TextConfigField({
    required super.key,
    required super.label,
    super.helperText,
    super.defaultValue,
    this.placeholder,
  });
}
// #enddocregion config-field-text-config-field

/// Multi-line text editor with optional moustache-tag chip hints.
// #docregion config-field-multiline-config-field
final class MultilineConfigField extends ConfigField {
  /// Suggested moustache tags displayed as hint chips under the editor.
  final List<String> moustacheTags;

  /// Minimum number of visible lines for the editor.
  final int? minLines;

  /// Maximum number of visible lines for the editor.
  final int? maxLines;

  /// Creates a multi-line text field schema.
  const MultilineConfigField({
    required super.key,
    required super.label,
    super.helperText,
    super.defaultValue,
    this.moustacheTags = const [],
    this.minLines = 6,
    this.maxLines = 14,
  });
}
// #enddocregion config-field-multiline-config-field

/// Obscured input with a show/hide toggle.
// #docregion config-field-password-config-field
final class PasswordConfigField extends ConfigField {
  /// Placeholder text shown when no value is set.
  final String? placeholder;

  /// Creates a password field schema with obscured input.
  const PasswordConfigField({
    required super.key,
    required super.label,
    super.helperText,
    super.defaultValue,
    this.placeholder,
  });
}
// #enddocregion config-field-password-config-field

/// Visual style for [NumberConfigField].
// #docregion config-field-number-field-style
enum NumberFieldStyle {
  /// Render as a slider with an inline value badge.
  slider,

  /// Render as a numeric text field. Bounds (when present) clamp the parsed
  /// value rather than constraining the slider.
  textInput,
}
// #enddocregion config-field-number-field-style

/// Numeric input.
///
/// When [style] is null (the default), the field auto-selects: slider if both
/// [min] AND [max] are non-null, text input otherwise. Set [style] explicitly
/// to force one mode regardless of bounds.
///
/// When [isInteger] is true, the value is stored as `int`, parsing strips
/// decimals, and slider steps default to 1.
// #docregion config-field-number-config-field
final class NumberConfigField extends ConfigField {
  /// Minimum numeric value allowed by the field.
  final double? min;

  /// Maximum numeric value allowed by the field.
  final double? max;

  /// Step size used when adjusting numeric values. When null and [isInteger]
  /// is true, defaults to 1.
  final double? step;

  /// Force a specific render style. Null = auto-pick from [min]/[max].
  final NumberFieldStyle? style;

  /// When true, values are stored as `int` and decimals are stripped.
  final bool isInteger;

  /// Creates a numeric field schema.
  const NumberConfigField({
    required super.key,
    required super.label,
    super.helperText,
    super.defaultValue,
    this.min,
    this.max,
    this.step,
    this.style,
    this.isInteger = false,
  });
}
// #enddocregion config-field-number-config-field

/// Typed dropdown.
// #docregion config-field-dropdown-config-field
final class DropdownConfigField<T> extends ConfigField {
  /// Allowed options rendered in the dropdown.
  final List<DropdownOption<T>> options;

  /// Creates a typed dropdown field schema.
  const DropdownConfigField({
    required super.key,
    required super.label,
    required this.options,
    super.helperText,
    super.defaultValue,
  });
}
// #enddocregion config-field-dropdown-config-field

/// A single selectable option for [DropdownConfigField].
// #docregion config-field-dropdown-option
class DropdownOption<T> {
  /// Runtime value assigned when this option is selected.
  final T value;

  /// Human-readable label shown in the menu.
  final String label;

  /// Creates a dropdown option.
  const DropdownOption(this.value, this.label);
}
// #enddocregion config-field-dropdown-option

/// Single switch.
// #docregion config-field-bool-config-field
final class BoolConfigField extends ConfigField {
  /// Creates a boolean switch field schema.
  const BoolConfigField({
    required super.key,
    required super.label,
    super.helperText,
    super.defaultValue,
  });
}
// #enddocregion config-field-bool-config-field

/// Visually groups a sub-set of fields under a sub-heading.
// #docregion config-field-group-config-field
final class GroupConfigField extends ConfigField {
  /// Child fields rendered inside the grouped section.
  final List<ConfigField> children;

  /// Creates a grouped field schema.
  const GroupConfigField({
    required super.key,
    required super.label,
    required this.children,
    super.helperText,
  });
}
// #enddocregion config-field-group-config-field

/// Escape hatch for custom field renderers.
///
/// The dialog locates a renderer registered under [rendererKey] and forwards
/// [args] to it. This keeps the field declaration Flutter-free; the custom
/// widget itself lives in a Flutter-side package that registers a
/// `ConfigFieldRenderer` for the same key with the dialog runtime.
// #docregion config-field-extension-config-field
final class ExtensionConfigField extends ConfigField {
  /// Identifier used to look up a renderer registered with the dialog runtime.
  final String rendererKey;

  /// Opaque, serializable arguments forwarded to the renderer.
  final Map<String, Object?> args;

  /// Creates an extension field schema.
  const ExtensionConfigField({
    required super.key,
    required super.label,
    required this.rendererKey,
    this.args = const {},
    super.helperText,
    super.defaultValue,
  });
}
// #enddocregion config-field-extension-config-field

/// Opaque handle exposed to field renderers for reading and writing the
/// current working value of a single field.
// #docregion config-field-config-field-handle
abstract class ConfigFieldHandle {
  /// Current working value for the bound field.
  Object? get value;

  /// Updates the current working value for the bound field.
  set value(Object? next);

  /// Whether the current value differs from the field default.
  bool get isOverridden;

  /// Restores the field value to its declared default.
  void reset();
}

// #enddocregion config-field-config-field-handle
