import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Obscured text renderer for a [PasswordConfigField].
class PasswordFieldInput extends StatefulWidget {
  /// Schema metadata for the password field.
  final PasswordConfigField field;

  /// Opaque handle used to read and write the current value.
  final ConfigFieldHandle handle;

  /// Creates a password-field renderer bound to [handle].
  const PasswordFieldInput({
    super.key,
    required this.field,
    required this.handle,
  });

  @override
  State<PasswordFieldInput> createState() => _PasswordFieldInputState();
}

class _PasswordFieldInputState extends State<PasswordFieldInput> {
  static const Duration _debounceDuration = Duration(milliseconds: 200);

  late final TextEditingController _controller;
  Timer? _debounce;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _asText(widget.handle.value));
  }

  @override
  void didUpdateWidget(covariant PasswordFieldInput oldWidget) {
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

  void _toggleObscureText() {
    setState(() {
      _obscureText = !_obscureText;
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
      obscureText: _obscureText,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        hintText: widget.field.placeholder,
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: 28,
          height: 28,
        ),
        suffixIcon: IconButton(
          onPressed: _toggleObscureText,
          icon: Icon(
            _obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 16,
          ),
          iconSize: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          visualDensity: VisualDensity.compact,
          splashRadius: 16,
          tooltip: _obscureText ? 'Show password' : 'Hide password',
        ),
      ),
    );
  }
}
