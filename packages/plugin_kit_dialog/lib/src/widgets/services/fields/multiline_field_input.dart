import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:plugin_kit/plugin_kit.dart';

/// Multi-line text editor for [MultilineConfigField] values.
class MultilineFieldInput extends StatefulWidget {
  /// Schema metadata driving editor behavior.
  final MultilineConfigField field;

  /// Mutable handle used to read and update the field value.
  final ConfigFieldHandle handle;

  /// Creates a multiline field input bound to [field] and [handle].
  const MultilineFieldInput({
    super.key,
    required this.field,
    required this.handle,
  });

  @override
  State<MultilineFieldInput> createState() => _MultilineFieldInputState();
}

class _MultilineFieldInputState extends State<MultilineFieldInput> {
  static const Duration _debounceDuration = Duration(milliseconds: 200);

  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text:
          widget.handle.value?.toString() ??
          widget.field.defaultValue?.toString() ??
          '',
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleWrite(String next) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      widget.handle.value = next;
    });
  }

  void _insertTag(String tag) {
    final insertion = '{{$tag}}';
    final selection = _controller.selection;
    final text = _controller.text;

    var start = selection.start;
    var end = selection.end;

    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }

    final rangeStart = min(start, end);
    final rangeEnd = max(start, end);
    final nextText = text.replaceRange(rangeStart, rangeEnd, insertion);
    final nextOffset = rangeStart + insertion.length;

    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
    _scheduleWrite(nextText);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          minLines: widget.field.minLines,
          maxLines: widget.field.maxLines,
          onChanged: _scheduleWrite,
        ),
        if (widget.field.moustacheTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Available moustache tags',
            style: textTheme.bodySmall?.copyWith(height: 1.3),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.field.moustacheTags
                .map(
                  (tag) => InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _insertTag(tag),
                    child: Chip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      label: Text(
                        tag,
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}
