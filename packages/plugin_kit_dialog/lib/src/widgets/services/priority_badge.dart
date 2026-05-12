import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../theme/plugin_kit_dialog_theme.dart';

/// Two-part pill showing plugin ownership and registration priority.
class PriorityBadge extends StatefulWidget {
  /// Plugin id that contributed the rendered service.
  final PluginId pluginId;

  /// Effective priority value for the winning registration.
  final int priority;

  /// Optional priority override currently stored in service settings.
  final int? overridePriority;

  /// Callback used to update or clear a priority override.
  final ValueChanged<int?>? onPriorityChanged;

  /// Creates a badge for [pluginId] and numeric [priority].
  const PriorityBadge({
    super.key,
    required this.pluginId,
    required this.priority,
    this.overridePriority,
    this.onPriorityChanged,
  });

  @override
  State<PriorityBadge> createState() => _PriorityBadgeState();
}

class _PriorityBadgeState extends State<PriorityBadge> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _editing = false;

  bool get _isEditable => widget.onPriorityChanged != null;

  int get _displayPriority => widget.overridePriority ?? widget.priority;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayPriority.toString());
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant PriorityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editing) {
      return;
    }
    final nextText = _displayPriority.toString();
    if (_controller.text != nextText) {
      _controller.text = nextText;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus || !_editing) {
      return;
    }
    _commitEditor();
  }

  void _startEditing() {
    if (!_isEditable || _editing) {
      return;
    }

    setState(() {
      _editing = true;
      _controller.text = _displayPriority.toString();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _commitEditor() {
    final next = int.tryParse(_controller.text.trim());
    // Only emit a change when the committed value is actually different from
    // what we're already showing. Opening the editor and clicking away (or
    // typing the same number) must NOT dirty the draft.
    if (next != null && next != _displayPriority) {
      widget.onPriorityChanged?.call(next);
    }
    _closeEditor();
  }

  void _clearOverride() {
    widget.onPriorityChanged?.call(null);
    _closeEditor();
  }

  void _closeEditor() {
    if (!_editing) {
      return;
    }
    setState(() {
      _editing = false;
    });
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.labelSmall;
    final leftColor = _pluginChipColor(context, widget.pluginId);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: leftColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(999),
                bottomLeft: Radius.circular(999),
              ),
            ),
            child: Text(widget.pluginId, style: textStyle),
          ),
          _editing
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 52,
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          style: textStyle,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _commitEditor(),
                        ),
                      ),
                      if (widget.overridePriority != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 18,
                            height: 18,
                          ),
                          tooltip: 'Use default priority',
                          onPressed: _clearOverride,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: textStyle?.color,
                          ),
                        ),
                    ],
                  ),
                )
              : InkWell(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(999),
                    bottomRight: Radius.circular(999),
                  ),
                  onTap: _isEditable ? _startEditing : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text('Priority $_displayPriority', style: textStyle),
                  ),
                ),
        ],
      ),
    );
  }

  Color _pluginChipColor(BuildContext context, PluginId pluginId) {
    final dialogTheme = PluginKitDialogTheme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final badgeBackground = colorScheme.surfaceContainerHighest;

    if (pluginId == const PluginId('core')) {
      return Color.alphaBlend(
        dialogTheme.stableAccent.withValues(alpha: 0.34),
        badgeBackground,
      );
    }

    final palette = [
      dialogTheme.stableAccent,
      colorScheme.primary,
      dialogTheme.experimentalAccent,
      dialogTheme.agentAccent,
    ];

    final index = pluginId.hashCode.abs() % palette.length;
    final accent = palette[index];
    return Color.alphaBlend(accent.withValues(alpha: 0.34), badgeBackground);
  }
}
