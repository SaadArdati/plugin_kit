import 'package:flutter/material.dart';

/// Material `Switch` scaled down for dense rows.
///
/// Two adjustments over a bare `Switch`:
///   1. `thumbIcon` carries a check glyph when selected so the thumb stays
///      visually distinct over the hovered track (M3-blessed fix for the
///      thumb-vanishes-on-hover issue, instead of nuking `overlayColor`).
///   2. `Transform.scale(0.6)` shrinks the switch to ~31×19 since M3 has no
///      native compact size. The outer `SizedBox` clamps layout height to
///      match the visual size, not the unscaled 32.
///
/// Color customization (unselected thumb / track outline) lives on the
/// canonical `ThemeData.switchTheme`, not here.
class CompactSwitch extends StatelessWidget {
  /// Current toggle state.
  final bool value;

  /// Callback invoked with the next toggle state when the user flips the
  /// switch.
  final ValueChanged<bool> onChanged;

  /// Creates a compact Material switch.
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Transform.scale(
        scale: 0.6,
        alignment: Alignment.center,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          thumbIcon: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? const Icon(Icons.check, size: 14)
                : null,
          ),
        ),
      ),
    );
  }
}
