import 'package:collection/collection.dart';

/// Type-safe, read-only accessor for service configuration values.
///
/// Wraps a `Map<String, dynamic>` with convenience methods that provide
/// automatic type conversion and null safety. The primary way
/// [PluginService]s access their injected settings.
///
/// The typed accessors ([getDouble], [getInt], [getBool]) coerce from
/// related types: `num` to `double` or `int`; `String` to `double`, `int`,
/// or `bool` via parsing; `num` to `bool` (0 = false, non-zero = true).
///
/// ```dart
/// final config = ConfigNode({
///   'verbose': true,
///   'timeout': 30,
///   'name': 'my_service',
///   'options': ['a', 'b', 'c'],
/// });
///
/// final verbose = config.getBool('verbose') ?? false;
/// final timeout = config.getInt('timeout') ?? 60;
/// final name = config.get<String>('name') ?? 'default';
/// final options = config.list<String>('options');
/// ```
///
/// The static [hashSettings] produces a stable hash from a settings map.
/// [ServiceRegistry] uses this to detect when singleton/lazy service
/// settings have actually changed, avoiding redundant
/// [PluginService.injectSettings] calls.
class ConfigNode {
  /// The underlying configuration data.
  final Map<String, dynamic> _node;

  /// Creates a config accessor for [_node].
  const ConfigNode(this._node);

  /// Returns the value at [key] if it is of type [T], otherwise null.
  T? get<T>(String key) {
    if (T == Map<String, dynamic>) {
      return map(key) as T?;
    }
    final v = _node[key];
    if (v is T) return v;
    return null;
  }

  /// Returns the string value for [key], or `null` if absent or not a string.
  String? getString(String key) => get<String>(key);

  /// Returns the value at [key] as a double. Coerces from `num` and parses
  /// string values; returns null on failure.
  double? getDouble(String key) {
    final v = _node[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Returns the value at [key] as an int. Coerces from `num` (truncating
  /// doubles) and parses string values; returns null on failure.
  int? getInt(String key) {
    final v = _node[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Returns the value at [key] as a bool. Accepts case-insensitive
  /// `'true'`/`'false'` strings and treats `0` as false, non-zero as true;
  /// returns null on failure.
  bool? getBool(String key) {
    final v = _node[key];
    if (v is bool) return v;
    if (v is String) {
      final lower = v.toLowerCase();
      if (lower == 'true') return true;
      if (lower == 'false') return false;
    }
    if (v is num) return v != 0;
    return null;
  }

  /// Returns the value at [key] as a `List<T>`, or `null` when the value
  /// is missing, not a list, or fails the element cast. Nullable so
  /// callers can fall back to a custom default via `??`:
  ///
  /// ```dart
  /// final tags = config.list<String>('tags') ?? const ['default'];
  /// ```
  ///
  /// Matches the failure mode of [get], [getString], [getInt],
  /// [getDouble], [getBool], and [map].
  List<T>? list<T>(String key) {
    final v = _node[key];
    if (v is List) {
      try {
        if (T == Map<String, dynamic>) {
          return List<T>.unmodifiable(
            v.cast<Map>().map(
              (item) =>
                  Map<String, dynamic>.from(item.cast<String, dynamic>()) as T,
            ),
          );
        }
        return List<T>.unmodifiable(v.cast<T>());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Returns the value at [key] as a `Map<String, dynamic>`, or `null`
  /// when the value is missing, not a map, or fails the cast. Nullable
  /// so callers can fall back to a custom default via `??`:
  ///
  /// ```dart
  /// final headers = config.map('headers') ?? const {'X-Default': '1'};
  /// ```
  ///
  /// Matches the failure mode of every other typed accessor on this
  /// class.
  Map<String, dynamic>? map(String key) {
    final v = _node[key];
    if (v is Map) {
      try {
        return Map<String, dynamic>.from(v.cast<String, dynamic>());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Whether [key] exists with a non-null value.
  bool has(String key) => _node.containsKey(key) && _node[key] != null;

  /// Returns the raw value at [key] without type conversion.
  dynamic raw(String key) => _node[key];

  /// All keys in this configuration node.
  Iterable<String> get keys => _node.keys;

  /// Whether this configuration node has no keys.
  bool get isEmpty => _node.isEmpty;

  /// Whether this configuration node has at least one key.
  bool get isNotEmpty => _node.isNotEmpty;

  /// Stable hex-encoded hash of [settings] using deep equality, suitable for
  /// cache invalidation when settings change.
  static String hashSettings(Map<String, dynamic> settings) {
    final hash = const DeepCollectionEquality().hash(settings);
    return hash.toRadixString(16);
  }
}
