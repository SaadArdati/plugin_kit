import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../controller/plugin_kit_dialog_controller.dart';
import '../../runtime/plugins/default_field_renderers_plugin.dart';
import '../shared/reset_button.dart';

/// Section that renders one [UiConfigurableCapability] with editable fields.
///
/// Does not own priority/reset controls: those live on the enclosing service
/// card header because priority is a service-level concept shared across all
/// capabilities of the same registration. When the service card has only one
/// capability, the outer card title already names it, so the caller passes
/// [showHeader] as false to suppress the inner header.
class ServiceFieldSection extends StatelessWidget {
  /// Capability schema defining title, subtitle, icon, and ordered fields.
  final UiConfigurableCapability capability;

  /// Plugin id that registered this capability.
  final PluginId pluginId;

  /// Dialog controller used to read and update working settings.
  final PluginKitDialogController controller;

  /// Scoped service key in `pluginId:serviceId` format.
  final Pin scopedKey;

  /// Whether field inputs should be interactive.
  final bool fieldsEnabled;

  /// Whether to render the inner header (icon + label + description).
  final bool showHeader;

  /// Resolves the field renderer for each [ConfigField].
  final FieldRenderResolver resolveRenderer;

  /// Creates one capability field section.
  const ServiceFieldSection({
    super.key,
    required this.capability,
    required this.pluginId,
    required this.controller,
    required this.scopedKey,
    this.fieldsEnabled = true,
    this.showHeader = true,
    required this.resolveRenderer,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final textTheme = Theme.of(context).textTheme;
        final colorScheme = Theme.of(context).colorScheme;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              Text(
                capability.label,
                style: textTheme.titleMedium?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
              if (capability.description != null) ...[
                const SizedBox(height: 2),
                Text(
                  capability.description!,
                  style: textTheme.bodyMedium?.copyWith(height: 1.3),
                ),
              ],
              const SizedBox(height: 4),
            ],
            IgnorePointer(
              ignoring: !fieldsEnabled,
              child: Opacity(
                opacity: fieldsEnabled ? 1.0 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final field in capability.fields)
                      _ServiceFieldRowEntry(
                        field: field,
                        controller: controller,
                        scopedKey: scopedKey,
                        resolveRenderer: resolveRenderer,
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One row in the field list. Builds the field handle, dispatches the
/// renderer, and wraps the result in [_ServiceFieldRow] chrome.
class _ServiceFieldRowEntry extends StatelessWidget {
  const _ServiceFieldRowEntry({
    required this.field,
    required this.controller,
    required this.scopedKey,
    required this.resolveRenderer,
  });

  final ConfigField field;
  final PluginKitDialogController controller;
  final Pin scopedKey;
  final FieldRenderResolver resolveRenderer;

  @override
  Widget build(BuildContext context) {
    final handle = _ControllerFieldHandle(
      controller: controller,
      scopedKey: scopedKey,
      fieldKey: field.key,
      defaultValue: field.defaultValue,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _ServiceFieldRow(
        field: field,
        isOverridden: handle.isOverridden,
        onReset: handle.reset,
        child: resolveRenderer(
          field,
        ).build(context, field, handle, resolveRenderer),
      ),
    );
  }
}

class _ServiceFieldRow extends StatelessWidget {
  const _ServiceFieldRow({
    required this.field,
    required this.child,
    required this.isOverridden,
    required this.onReset,
  });

  final ConfigField field;
  final Widget child;
  final bool isOverridden;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (field is BoolConfigField) {
      return Row(
        children: [
          Expanded(child: child),
          const SizedBox(width: 8),
          ResetButton(isOverridden: isOverridden, onReset: onReset),
        ],
      );
    }

    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              field.label,
              style: textTheme.labelMedium?.copyWith(height: 1.1),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: field.helperText != null
                    ? Text(
                        field.helperText!,
                        style: textTheme.bodySmall?.copyWith(height: 1.1),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 6),
            ResetButton(isOverridden: isOverridden, onReset: onReset),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ControllerFieldHandle implements ConfigFieldHandle {
  _ControllerFieldHandle({
    required this.controller,
    required this.scopedKey,
    required this.fieldKey,
    required this.defaultValue,
  });

  final PluginKitDialogController controller;
  final Pin scopedKey;
  final String fieldKey;
  final Object? defaultValue;

  @override
  Object? get value {
    final config = controller.draft.working.services[scopedKey]?.config;
    final configuredValue = _readNestedValue(config, fieldKey);
    return configuredValue ?? defaultValue;
  }

  @override
  set value(Object? next) {
    controller.setServiceField(
      scopedKey: scopedKey,
      fieldKey: fieldKey,
      value: next,
    );
  }

  @override
  bool get isOverridden {
    final config = controller.draft.working.services[scopedKey]?.config;
    final configuredValue = _readNestedValue(config, fieldKey);
    if (configuredValue == null) {
      return false;
    }
    return !_deepEquals(configuredValue, defaultValue);
  }

  @override
  void reset() => controller.resetField(scopedKey, fieldKey);

  Object? _readNestedValue(Map<String, dynamic>? source, String dottedKey) {
    if (source == null || source.isEmpty) {
      return null;
    }

    final segments = dottedKey
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return null;
    }

    if (segments.length == 1) {
      return source[segments.first];
    }

    Object? current = source;
    for (final segment in segments) {
      if (current is Map<String, dynamic>) {
        current = current[segment];
      } else if (current is Map) {
        current = current[segment];
      } else {
        return null;
      }
    }

    return current;
  }

  bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) {
      return true;
    }

    if (a is Map && b is Map) {
      if (a.length != b.length) {
        return false;
      }
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
          return false;
        }
      }
      return true;
    }

    if (a is List && b is List) {
      if (a.length != b.length) {
        return false;
      }
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) {
          return false;
        }
      }
      return true;
    }

    if (a is Set && b is Set) {
      if (a.length != b.length) {
        return false;
      }
      for (final value in a) {
        if (!b.contains(value)) {
          return false;
        }
      }
      return true;
    }

    return a == b;
  }
}
