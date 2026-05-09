import 'package:flutter/material.dart';

import 'package:plugin_kit/plugin_kit.dart';

/// Dropdown renderer for a typed [DropdownConfigField].
class DropdownFieldInput<T> extends StatelessWidget {
  /// Field schema describing the dropdown label and options.
  final DropdownConfigField<T> field;

  /// Value handle used to read and write the field state.
  final ConfigFieldHandle handle;

  /// Creates a dropdown field input bound to [field] and [handle].
  const DropdownFieldInput({
    super.key,
    required this.field,
    required this.handle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Merge with the theme's bodyMedium so the dropdown inherits whatever
    // `fontFamily` the host app set on its `TextTheme`. Constructing a bare
    // `TextStyle` here would skip that inheritance, which leaves the dropdown
    // text using the platform default font (and renders as glyph-less blocks
    // in environments that have not loaded one, such as golden tests).
    final textStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
          height: 1.2,
        );

    return DropdownButtonFormField<T>(
      initialValue: handle.value as T?,
      isDense: true,
      isExpanded: true,
      style: textStyle,
      iconSize: 18,
      iconEnabledColor: colorScheme.onSurfaceVariant,
      items: field.options
          .map(
            (option) => DropdownMenuItem<T>(
              value: option.value,
              child: Text(option.label, style: textStyle),
            ),
          )
          .toList(growable: false),
      onChanged: (newValue) => handle.value = newValue,
    );
  }
}
