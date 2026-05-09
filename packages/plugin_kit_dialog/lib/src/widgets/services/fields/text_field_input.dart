import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Single-line text renderer for a [TextConfigField].
class TextFieldInput extends StatefulWidget {
  /// Schema metadata for the text field.
  final TextConfigField field;

  /// Opaque handle used to read and write the current value.
  final ConfigFieldHandle handle;

  /// Creates a text-field renderer bound to [handle].
  const TextFieldInput({super.key, required this.field, required this.handle});

  @override
  State<TextFieldInput> createState() => _TextFieldInputState();
}

class _TextFieldInputState extends State<TextFieldInput> {
  static const Duration _debounceDuration = Duration(milliseconds: 200);

  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _asText(widget.handle.value));
  }

  @override
  void didUpdateWidget(covariant TextFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle == widget.handle) {
      return;
    }
    final nextText = _asText(widget.handle.value);
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      widget.handle.value = value;
    });
  }

  String _asText(Object? value) {
    if (value == null) {
      return '';
    }
    return value is String ? value : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      decoration: InputDecoration(hintText: widget.field.placeholder),
    );
  }
}
