import 'dart:async';

import 'package:flutter/material.dart';

import 'package:plugin_kit/plugin_kit.dart';

/// Numeric editor for [NumberConfigField] values.
class NumberFieldInput extends StatefulWidget {
  /// Schema metadata driving slider/text behavior.
  final NumberConfigField field;

  /// Mutable handle used to read and update the field value.
  final ConfigFieldHandle handle;

  /// Creates a number field input bound to [field] and [handle].
  const NumberFieldInput({
    super.key,
    required this.field,
    required this.handle,
  });

  @override
  State<NumberFieldInput> createState() => _NumberFieldInputState();
}

class _NumberFieldInputState extends State<NumberFieldInput> {
  static const Duration _debounceDuration = Duration(milliseconds: 200);

  Timer? _debounce;
  TextEditingController? _textController;
  late double _sliderValue;

  bool get _usesSlider {
    final style = widget.field.style;
    if (style == NumberFieldStyle.slider) {
      return widget.field.min != null && widget.field.max != null;
    }
    if (style == NumberFieldStyle.textInput) {
      return false;
    }
    return widget.field.min != null && widget.field.max != null;
  }

  num _coerceForWrite(double value) {
    return widget.field.isInteger ? value.round() : value;
  }

  @override
  void initState() {
    super.initState();

    if (_usesSlider) {
      _sliderValue = _resolveInitialSliderValue();
    } else {
      _textController = TextEditingController(text: _resolveInitialTextValue());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController?.dispose();
    super.dispose();
  }

  void _scheduleWrite(Object? next) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      widget.handle.value = next;
    });
  }

  double _resolveInitialSliderValue() {
    final min = widget.field.min!;
    final max = widget.field.max!;
    final parsed =
        _parseDouble(widget.handle.value) ??
        _parseDouble(widget.field.defaultValue) ??
        min;
    final clamped = parsed.clamp(min, max).toDouble();
    return _snapToStep(clamped);
  }

  String _resolveInitialTextValue() {
    final parsed =
        _parseDouble(widget.handle.value) ??
        _parseDouble(widget.field.defaultValue);
    if (parsed == null) {
      return '';
    }
    return _formatNumber(parsed);
  }

  double? _parseDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  double? _effectiveStep() {
    final declared = widget.field.step;
    if (declared != null && declared > 0) {
      return declared;
    }
    return widget.field.isInteger ? 1.0 : null;
  }

  double _snapToStep(double value) {
    final min = widget.field.min;
    final step = _effectiveStep();

    if (min == null || step == null) {
      return widget.field.isInteger ? value.roundToDouble() : value;
    }

    final snapped = min + (((value - min) / step).roundToDouble() * step);
    final max = widget.field.max;

    if (max == null) {
      return snapped;
    }

    return snapped.clamp(min, max).toDouble();
  }

  int? _sliderDivisions() {
    final min = widget.field.min;
    final max = widget.field.max;
    final step = _effectiveStep();

    if (min == null || max == null || step == null || max <= min) {
      return null;
    }

    final divisions = ((max - min) / step).round();
    return divisions > 0 ? divisions : null;
  }

  String _formatNumber(double value) {
    if (widget.field.isInteger || value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _handleSliderChanged(double value) {
    final next = _snapToStep(value);
    setState(() {
      _sliderValue = next;
    });
    _scheduleWrite(_coerceForWrite(next));
  }

  void _handleTextChanged(String raw) {
    final trimmed = raw.trim();

    if (trimmed.isEmpty) {
      _scheduleWrite(null);
      return;
    }

    final parsed = widget.field.isInteger
        ? (int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round())
        : double.tryParse(trimmed);
    if (parsed == null) {
      return;
    }

    final clamped = _clampToBounds(parsed.toDouble());
    _scheduleWrite(_coerceForWrite(clamped));
  }

  double _clampToBounds(double value) {
    final min = widget.field.min;
    final max = widget.field.max;
    if (min != null && value < min) return min;
    if (max != null && value > max) return max;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    if (_usesSlider) {
      final colorScheme = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;

      return SizedBox(
        height: 32,
        child: Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  min: widget.field.min!,
                  max: widget.field.max!,
                  divisions: _sliderDivisions(),
                  value: _sliderValue,
                  onChanged: _handleSliderChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.outline),
              ),
              child: Text(
                _formatNumber(_sliderValue),
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 34,
      child: TextField(
        controller: _textController,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !widget.field.isInteger,
          signed: (widget.field.min ?? 0) < 0,
        ),
        onChanged: _handleTextChanged,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }
}
