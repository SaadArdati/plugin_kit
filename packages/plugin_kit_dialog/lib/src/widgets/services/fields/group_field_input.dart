import 'package:flutter/widgets.dart';

import 'package:plugin_kit/plugin_kit.dart';
import '../../../runtime/plugins/default_field_renderers_plugin.dart';

/// Renderer for [GroupConfigField] that delegates each child to its renderer.
class GroupFieldInput extends StatelessWidget {
  /// Group field schema to render.
  final GroupConfigField field;

  /// Handle for the bound group-map value.
  final ConfigFieldHandle handle;

  /// Resolves child renderers for [field.children].
  final FieldRenderResolver resolveRenderer;

  /// Creates a grouped field input renderer.
  const GroupFieldInput({
    required this.field,
    required this.handle,
    required this.resolveRenderer,
    super.key,
  });

  /// Builds one rendered row per child field.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < field.children.length; index++) ...[
          _GroupChildFieldRow(
            field: field.children[index],
            child: resolveRenderer(field.children[index]).build(
              context,
              field.children[index],
              _GroupChildFieldHandle(
                parentHandle: handle,
                field: field.children[index],
              ),
              resolveRenderer,
            ),
          ),
          if (index != field.children.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _GroupChildFieldRow extends StatelessWidget {
  const _GroupChildFieldRow({required this.field, required this.child});

  final ConfigField field;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (field is BoolConfigField) {
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label),
        if (field.helperText case final helperText?) ...[
          const SizedBox(height: 4),
          Text(helperText),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _GroupChildFieldHandle implements ConfigFieldHandle {
  _GroupChildFieldHandle({required this.parentHandle, required this.field});

  final ConfigFieldHandle parentHandle;
  final ConfigField field;

  @override
  Object? get value {
    final groupValue = _readDottedValue(_currentGroupValue, field.key);
    return groupValue ?? field.defaultValue;
  }

  @override
  set value(Object? next) {
    final nextGroupValue = _setDottedValue(_currentGroupValue, field.key, next);
    parentHandle.value = nextGroupValue.isEmpty ? null : nextGroupValue;
  }

  @override
  bool get isOverridden {
    final configuredValue = _readDottedValue(_currentGroupValue, field.key);
    if (configuredValue == null) {
      return false;
    }
    return !_deepEquals(configuredValue, field.defaultValue);
  }

  @override
  void reset() => value = null;

  Map<String, dynamic> get _currentGroupValue {
    final current = parentHandle.value;
    if (current is Map<String, dynamic>) {
      return Map<String, dynamic>.from(current);
    }
    if (current is Map) {
      return current.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _setDottedValue(
    Map<String, dynamic> source,
    String dottedKey,
    Object? value,
  ) {
    final segments = dottedKey
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      return Map<String, dynamic>.from(source);
    }

    final root = Map<String, dynamic>.from(source);
    _setRecursive(root, segments, value);
    return root;
  }

  void _setRecursive(
    Map<String, dynamic> node,
    List<String> segments,
    Object? value,
  ) {
    final key = segments.first;
    if (segments.length == 1) {
      if (value == null) {
        node.remove(key);
      } else {
        node[key] = value;
      }
      return;
    }

    final existingChild = node[key];
    final child = switch (existingChild) {
      Map<String, dynamic>() => Map<String, dynamic>.from(existingChild),
      Map() => existingChild.map(
        (childKey, childValue) => MapEntry(childKey.toString(), childValue),
      ),
      _ => <String, dynamic>{},
    };

    _setRecursive(child, segments.sublist(1), value);

    if (child.isEmpty) {
      node.remove(key);
    } else {
      node[key] = child;
    }
  }

  Object? _readDottedValue(Map<String, dynamic> source, String dottedKey) {
    final segments = dottedKey
        .split('.')
        .where((segment) => segment.isNotEmpty);
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
