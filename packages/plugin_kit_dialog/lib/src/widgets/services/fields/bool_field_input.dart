import 'package:flutter/material.dart';

import 'package:plugin_kit/plugin_kit.dart';
import '../../shared/compact_switch.dart';

/// Boolean switch renderer for [BoolConfigField].
class BoolFieldInput extends StatelessWidget {
  /// Field schema describing the switch label and helper text.
  final BoolConfigField field;

  /// Value handle used to read and write the field state.
  final ConfigFieldHandle handle;

  /// Creates a boolean field input bound to [field] and [handle].
  const BoolFieldInput({super.key, required this.field, required this.handle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CompactSwitch(
          value: (handle.value as bool?) ?? false,
          onChanged: (next) => handle.value = next,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            field.label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        if (field.helperText != null)
          Tooltip(
            message: field.helperText!,
            child: Icon(
              Icons.info_outline,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
