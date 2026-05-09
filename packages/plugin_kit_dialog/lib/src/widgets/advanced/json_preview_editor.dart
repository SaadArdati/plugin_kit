import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../controller/plugin_kit_dialog_controller.dart';
import '../../theme/plugin_kit_dialog_theme.dart';
import '../shared/plugin_kit_dialog_card.dart';
import '../shared/section_header.dart';

/// Editable JSON view of [PluginKitDialogController.draft] with debounced sync.
///
/// The controller draft is the single source of truth. This widget keeps a
/// transient text buffer for in-progress edits and only writes parsed settings
/// back when the debounce timer fires and validation succeeds.
class JsonPreviewEditor extends StatefulWidget {
  /// Controller whose working draft is edited by this JSON preview.
  final PluginKitDialogController controller;

  /// Creates a JSON preview/editor bound to [controller].
  const JsonPreviewEditor({required this.controller, super.key});

  @override
  State<JsonPreviewEditor> createState() => _JsonPreviewEditorState();
}

class _JsonPreviewEditorState extends State<JsonPreviewEditor> {
  static const Duration _debounceDuration = Duration(milliseconds: 300);
  static const DeepCollectionEquality _deepEquality = DeepCollectionEquality();

  late final TextEditingController _text;
  late final FocusNode _focus;
  String? _parseError;

  /// Debounce timer that coalesces rapid typing before JSON parsing.
  Timer? _debounce;

  bool get _editorFocused => _focus.hasFocus;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: _encodeEditable(widget.controller.draft.working),
    );
    _focus = FocusNode();

    widget.controller.addListener(_onControllerChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant JsonPreviewEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) {
      return;
    }

    oldWidget.controller.removeListener(_onControllerChanged);
    widget.controller.addListener(_onControllerChanged);

    if (!_editorFocused) {
      _setEditorText(_encodeEditable(widget.controller.draft.working));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focus.removeListener(_onFocusChanged);
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onUserTyped(String _) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, _onDebounceFired);
  }

  void _onDebounceFired() {
    try {
      final decoded = _decodeRootObject(_text.text);
      final parsed = RuntimeSettings.fromJson(decoded);
      final mismatch = _shapeMismatch(decoded, parsed);
      if (mismatch != null) {
        _setParseError('Settings shape mismatch: $mismatch');
        return;
      }

      widget.controller.replaceWorking(parsed);
      _clearParseError();
    } on FormatException catch (error) {
      _setParseError(error.message);
    } on Object catch (error) {
      _setParseError(error.toString());
    }
  }

  void _onFocusChanged() {
    if (_editorFocused) {
      return;
    }

    if (_parseError != null) {
      _setEditorText(_encodeEditable(widget.controller.draft.working));
      _clearParseError();
    }
  }

  void _onControllerChanged() {
    if (!_editorFocused) {
      _setEditorText(_encodeEditable(widget.controller.draft.working));
    }
    if (mounted) {
      setState(() {});
    }
  }

  Map<String, dynamic> _decodeRootObject(String rawText) {
    final decoded = jsonDecode(rawText);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object at the root.');
    }

    return decoded.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String? _shapeMismatch(Map<String, dynamic> decoded, RuntimeSettings parsed) {
    final encoded = parsed.toJson();
    final roundTripped = RuntimeSettings.fromJson(encoded).toJson();

    if (!_deepEquality.equals(encoded, roundTripped)) {
      return _firstMismatch(encoded, roundTripped);
    }

    if (!_deepEquality.equals(decoded, encoded)) {
      return _firstMismatch(decoded, encoded);
    }

    return null;
  }

  String _firstMismatch(Object? left, Object? right, [String path = r'$']) {
    if (left is Map && right is Map) {
      final leftKeys = left.keys.map((key) => key.toString()).toSet();
      final rightKeys = right.keys.map((key) => key.toString()).toSet();

      final missing = leftKeys.difference(rightKeys);
      if (missing.isNotEmpty) {
        return '$path.${missing.first}';
      }

      final extra = rightKeys.difference(leftKeys);
      if (extra.isNotEmpty) {
        return '$path.${extra.first}';
      }

      final orderedKeys = left.keys.map((key) => key.toString()).toList();
      for (final key in orderedKeys) {
        final leftValue = left[key];
        final rightValue = right[key];
        if (!_deepEquality.equals(leftValue, rightValue)) {
          return _firstMismatch(leftValue, rightValue, '$path.$key');
        }
      }
      return path;
    }

    if (left is List && right is List) {
      if (left.length != right.length) {
        return '$path[length]';
      }
      for (var index = 0; index < left.length; index++) {
        if (!_deepEquality.equals(left[index], right[index])) {
          return _firstMismatch(left[index], right[index], '$path[$index]');
        }
      }
      return path;
    }

    return path;
  }

  void _setEditorText(String text) {
    if (_text.text == text) {
      return;
    }

    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  void _setParseError(String message) {
    if (!mounted || _parseError == message) {
      return;
    }

    setState(() {
      _parseError = message;
    });
  }

  void _clearParseError() {
    if (!mounted || _parseError == null) {
      return;
    }

    setState(() {
      _parseError = null;
    });
  }

  /// Show-all expansion is display-only; the editor always serializes the
  /// actual draft working settings to avoid persisting synthetic defaults.
  String _encodeEditable(RuntimeSettings settings) {
    return const JsonEncoder.withIndent('  ').convert(settings.toJson());
  }

  String _encodeExpanded(RuntimeSettings settings) {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(_expandedSettings(settings).toJson());
  }

  RuntimeSettings _expandedSettings(RuntimeSettings working) {
    final plugins = _defaultPluginConfigs()..addAll(working.plugins);
    final services = _defaultServiceSettings()..addAll(working.services);
    return RuntimeSettings(plugins: plugins, services: services);
  }

  Map<PluginId, PluginConfig> _defaultPluginConfigs() {
    final defaults = <PluginId, PluginConfig>{};
    for (final plugin in widget.controller.runtime.plugins) {
      final flags = plugin.featureFlags;
      final enabled =
          flags.contains(FeatureFlag.locked) ||
          !flags.contains(FeatureFlag.experimental);
      defaults[plugin.pluginId] = PluginConfig(enabled: enabled);
    }
    return defaults;
  }

  Map<Pin, ServiceSettings> _defaultServiceSettings() {
    final registry = _resolveTargetRegistry(widget.controller.runtime);
    if (registry == null) {
      return <Pin, ServiceSettings>{};
    }

    final defaults = <Pin, ServiceSettings>{};
    final registrations = registry.getAllResolvedRegistrations();
    for (final entry in registrations.entries) {
      final wrapper = entry.value;
      defaults[wrapper.pluginId.service(entry.key)] = const ServiceSettings();
    }
    return defaults;
  }

  ServiceRegistry? _resolveTargetRegistry(PluginRuntime targetRuntime) {
    if (targetRuntime.sessions.isNotEmpty) {
      return targetRuntime.sessions.last.registry;
    }

    try {
      return targetRuntime.globalRegistry;
    } on Error {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cardRadius = theme.cardBorderRadius;
    final editorStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.35);
    final errorTextStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.error);
    final showExpandedPreview = widget.controller.showAllServices;
    final expandedPreviewText = showExpandedPreview
        ? _encodeExpanded(widget.controller.draft.working)
        : null;

    return PluginKitDialogCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: Icons.code,
            iconBackground: colorScheme.primary,
            title: 'JSON Preview',
          ),
          if (_parseError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.42),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_parseError!, style: errorTextStyle)),
                ],
              ),
            ),
          ],
          if (showExpandedPreview && expandedPreviewText != null) ...[
            const SizedBox(height: 12),
            Text(
              'Expanded (read-only)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                borderRadius: cardRadius,
                border: Border.all(color: colorScheme.outline),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    expandedPreviewText,
                    style: editorStyle,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 8,
            maxLines: null,
            style: editorStyle,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerLowest,
              enabledBorder: OutlineInputBorder(
                borderRadius: cardRadius,
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: cardRadius,
                borderSide: BorderSide(color: colorScheme.primary),
              ),
            ),
            onChanged: _onUserTyped,
          ),
        ],
      ),
    );
  }
}
