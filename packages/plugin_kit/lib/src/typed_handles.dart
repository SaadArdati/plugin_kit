/// Typed plugin identifier. Wraps the plugin id as a String. Like
/// [Namespace] and [ServiceId], a zero-cost extension type -- at runtime,
/// it IS the underlying String. Because [PluginId] declares
/// `implements String`, it flows directly into any `String`-typed
/// parameter, JSON serialization key, or comparison without needing to
/// reach for [value]. Equality and `toString()` delegate to the
/// underlying String, so `==` against a String literal works.
///
/// PluginId values starting with `__pk_` are reserved for internal sentinels
/// like [PluginId.wildcard] and [PluginId.winnerScoped]. Plugin authors must
/// not use this prefix; the runtime rejects such ids on registration.
extension type const PluginId(String value) implements String {
  /// Sentinel plugin id representing "any plugin" in wildcard service
  /// overrides. Serialized as `*` on the wire (see [Pin.wire]);
  /// the runtime translates this to [winnerScoped] when applying overrides.
  /// Do not use as a real plugin id.
  static const PluginId wildcard = PluginId('__pk_wildcard__');

  /// Internal sentinel plugin id used by the runtime override list to key
  /// "winner-scoped" entries (overrides that apply to whichever plugin
  /// currently wins resolution rather than targeting a specific plugin).
  ///
  /// During settings reconciliation the runtime translates [wildcard] keys
  /// from the wire into entries keyed under this sentinel, so
  /// `_overrideForInjection`'s fallback can find the wildcard's config for
  /// any future winner. Never appears on the wire; plugin authors do not
  /// register or resolve under it. Exposed so test code can assert
  /// "this override is winner-scoped" without a private duplicate.
  static const PluginId winnerScoped = PluginId('__pk_winner__');

  /// Returns a [Pin] pairing this plugin with [serviceId]. Reads tightly
  /// when the receiver is obviously a [PluginId]:
  ///
  /// ```dart
  /// final pin = const PluginId('chat').service(
  ///   const ServiceId('agent.model'),
  /// );
  /// // pin.wire == 'chat:agent.model'
  /// ```
  ///
  /// Works with [PluginId.wildcard] to produce a wildcard pin
  /// (`'*:serviceId'` on the wire):
  ///
  /// ```dart
  /// final any = PluginId.wildcard.service(const ServiceId('agent.tools'));
  /// // any.isWildcard == true
  /// ```
  Pin service(String serviceId) {
    final p = this == PluginId.wildcard ? '*' : this;
    return Pin.fromWire('$p:$serviceId');
  }

  /// Pairs this plugin with the namespace [name], returning a
  /// [PluginNamespaced] handle that can chain into a leaf [Pin].
  ///
  /// ```dart
  /// final pin = const PluginId('chat').namespace('agent').service('model');
  /// // pin.wire == 'chat:agent.model'
  /// ```
  ///
  /// Chain [PluginNamespaced.child] to deepen the namespace, or
  /// [PluginNamespaced.call] / [PluginNamespaced.service] to finalise.
  PluginNamespaced namespace(String name) =>
      PluginNamespaced(this, Namespace(name));
}

/// Intermediate handle returned by [PluginId.namespace]: a plugin paired
/// with a namespace, ready to produce a [Pin] for any leaf service id
/// inside that namespace.
///
/// ```dart
/// final agent = const PluginId('chat').namespace('agent');
/// final model = agent.service('model');             // wire 'chat:agent.model'
/// final scope = agent.child('system_prompt')('scope');
/// // scope.wire == 'chat:agent.system_prompt.scope'
/// ```
class PluginNamespaced {
  /// Pair [pluginId] with [namespace].
  const PluginNamespaced(this.pluginId, this.namespace);

  /// The plugin half of the pair.
  final PluginId pluginId;

  /// The namespace half of the pair.
  final Namespace namespace;

  /// Returns a [Pin] for the leaf service [id] inside [namespace], owned
  /// by [pluginId]. Wire form: `'<pluginId>:<namespace>.<id>'`.
  Pin service(String id) {
    final p = pluginId == PluginId.wildcard ? '*' : pluginId;
    return Pin.fromWire('$p:$namespace.$id');
  }

  /// Shorthand for [service]: `pluginNs('id')` returns
  /// `pluginNs.service('id')`. Reads tightly when the receiver is
  /// obviously a [PluginNamespaced]:
  ///
  /// ```dart
  /// final scope = const PluginId('chat').namespace('agent')('model');
  /// // scope.wire == 'chat:agent.model'
  /// ```
  Pin call(String id) => service(id);

  /// Returns a deeper [PluginNamespaced] by appending [name] under the
  /// current namespace with a `.` separator.
  ///
  /// ```dart
  /// const PluginId('chat')
  ///     .namespace('agent')
  ///     .child('system_prompt')
  ///     .service('scope');
  /// // wire 'chat:agent.system_prompt.scope'
  /// ```
  PluginNamespaced child(String name) =>
      PluginNamespaced(pluginId, namespace.child(name));
}

/// Typed namespace identifier. Wraps the namespace name as a String. Like
/// [PluginId] and [ServiceId], a zero-cost extension type -- at runtime,
/// it IS the underlying String, so `==` against a String literal works
/// and `Map<Namespace, ...>` keys hash and compare by the wrapped String.
///
/// Use [child] to compose nested namespaces and [service] to produce a
/// [ServiceId] inside this namespace:
///
/// ```dart
/// const agent = Namespace('agent');
/// final fileTree = agent.child('system_prompt').child('file_tree');
/// final scope = fileTree.service('scope');
/// // ServiceId('agent.system_prompt.file_tree.scope')
/// ```
extension type const Namespace(String value) implements String {
  /// Returns a sub-namespace by appending [name] under this one with a `.`
  /// separator. Use to compose nested namespaces:
  ///
  /// ```dart
  /// const agent = Namespace('agent');
  /// final sysPrompt = agent.child('system_prompt');
  /// // Namespace('agent.system_prompt')
  /// ```
  Namespace child(String name) => Namespace('$value.$name');

  /// Returns a [ServiceId] for the slot named [id] inside this namespace.
  /// Equivalent to `ServiceId.namespaced(this, id)` at runtime. This method
  /// is not `const`; for const contexts use `ServiceId.namespaced(...)`
  /// directly.
  ///
  /// ```dart
  /// const agent = Namespace('agent');
  /// registry.registerSingleton(agent.service('model'), () => ModelImpl());
  /// context.resolve<Model>(agent.service('model'));
  /// ```
  ServiceId service(String id) => ServiceId('$value.$id');

  /// Shorthand for [service]: `agent('model')` returns
  /// `ServiceId('agent.model')`. Reads tightly at the call site when the
  /// receiver is obviously a [Namespace]:
  ///
  /// ```dart
  /// const agent = Namespace('agent');
  /// registry.registerSingleton(agent('model'), () => ModelImpl());
  /// context.resolve<Model>(agent('model'));
  /// ```
  ServiceId call(String id) => service(id);

  /// Whether [id] lives anywhere under this namespace. Matches direct
  /// children and nested descendants alike: `Namespace('agent').has(...)`
  /// returns true for both `ServiceId('agent.model')` and
  /// `ServiceId('agent.system_prompt.scope')`, and false for
  /// `ServiceId('agentic.model')` or `ServiceId('agent')` (the flat id
  /// that happens to match the namespace name).
  bool has(ServiceId id) => id.startsWith('$value.');
}

/// Typed service-slot identifier.
///
/// Wraps the registry key as a String. Like [PluginId] and [Namespace], a
/// zero-cost extension type -- at runtime, it IS the underlying String, so
/// `Map<ServiceId, ...>` keys hash and compare by the wrapped String, and
/// `==` against a String literal works.
///
/// Construct directly when there is no namespace:
///
/// ```dart
/// const id = ServiceId('main_db');
/// ```
///
/// Use [ServiceId.namespaced] (or the equivalent [Namespace.service]) to
/// combine a namespace and an id:
///
/// ```dart
/// const agent = Namespace('agent');
/// const model = ServiceId.namespaced(agent, 'model'); // 'agent.model'
/// const sameKey = ServiceId('agent.model');           // identical key
/// ```
///
/// Two ServiceIds compare equal when their wrapped Strings compare equal,
/// so the two forms above resolve to the same registry slot.
///
/// The structure ([namespace] and [id]) can be queried lazily; both getters
/// parse [value] on demand using the LAST `.` as the separator, which
/// handles nested namespaces (`'a.b.c.d'` -> namespace `'a.b.c'`, id `'d'`).
extension type const ServiceId(String value) implements String {
  /// Builds a [ServiceId] inside [ns] with leaf [id]. The result is the
  /// concatenation `'$ns.$id'`. Equivalent to `ns.service(id)`, but usable
  /// in `const` contexts.
  const ServiceId.namespaced(Namespace ns, String id) : this('$ns.$id');

  /// The full namespace prefix (everything before the last `.` in [value]),
  /// or `null` when [value] has no `.`. The split uses `lastIndexOf` so
  /// nested keys like `'a.b.c'` return `Namespace('a.b')` and `id` returns
  /// `'c'`.
  ///
  /// For UI grouping that should flatten nested keys under their top-level
  /// segment (e.g. show `'agent.system_prompt.scope'` under `'agent'`), use
  /// [topNamespace] instead.
  ///
  /// A leading `.` (e.g. `'.weird'`) is treated as no namespace.
  Namespace? get namespace {
    final i = value.lastIndexOf('.');
    return i <= 0 ? null : Namespace(value.substring(0, i));
  }

  /// The leaf segment after the last `.`, or the full [value] when there is
  /// no `.`. Mirrors the split used by [namespace]; for `'a.b.c'` the leaf
  /// is `'c'`.
  ///
  /// A leading `.` (e.g. `'.weird'`) returns the full key unchanged.
  String get id {
    final i = value.lastIndexOf('.');
    return i <= 0 ? value : value.substring(i + 1);
  }

  /// The top-level namespace segment (everything before the FIRST `.` in
  /// [value]), or `null` when [value] has no `.`. Use for UI grouping where
  /// nested keys should flatten under their first segment, e.g.
  /// `'agent.system_prompt.scope'` groups under `Namespace('agent')`.
  /// Differs from [namespace] which returns the full nested prefix
  /// (`Namespace('agent.system_prompt')`).
  ///
  /// A leading `.` (e.g. `'.weird'`) is treated as no namespace.
  Namespace? get topNamespace {
    final i = value.indexOf('.');
    return i <= 0 ? null : Namespace(value.substring(0, i));
  }
}

/// A typed key identifying "the [serviceId] registered by [pluginId]".
/// The map key type used by `RuntimeSettings.services` and any other
/// place that needs to address a single plugin's service slot.
///
/// At runtime, `Pin` IS the canonical wire string `'<pluginId>:<serviceId>'`
/// (with `'*'` for [PluginId.wildcard]), so map equality, hashing, and JSON
/// serialization round-trip with no conversion.
///
/// Construct one of three ways:
///
/// ```dart
/// // Primary: plugin id + segments of the service id (joined with '.').
/// Pin('chat', ['agent', 'model']);              // wire 'chat:agent.model'
/// Pin('chat', ['greeter']);                     // wire 'chat:greeter'
///
/// // Wildcard form (any plugin currently winning the slot).
/// Pin.wildcard(['agent', 'tools']);             // wire '*:agent.tools'
///
/// // Parse the wire format (used by RuntimeSettings.fromJson).
/// Pin.fromWire('chat:agent.model');
///
/// // From the typed chain on PluginId. Same Pin under the hood.
/// const PluginId('chat').service(const ServiceId('agent.model'));
/// const PluginId('chat').namespace('agent').service('model');
/// PluginId.wildcard.service(const ServiceId('agent.tools'));
/// ```
///
/// Inspect via [pluginId], [serviceId], [isWildcard], [wire]. The first two
/// parse on demand and throw [FormatException] on a malformed wire string.
extension type const Pin._(String _value) implements String {
  /// Pin a service to a plugin. [serviceIdSegments] are joined with `'.'`
  /// to form the service-id portion of the wire format.
  ///
  /// Pass `'*'` as [pluginId] for the wildcard form, or prefer
  /// [Pin.wildcard] for explicit intent.
  factory Pin(String pluginId, List<String> serviceIdSegments) =>
      Pin._('$pluginId:${serviceIdSegments.join('.')}');

  /// Wildcard pin: targets whichever plugin currently wins the slot.
  /// [serviceIdSegments] are joined with `'.'`.
  factory Pin.wildcard(List<String> serviceIdSegments) =>
      Pin._('*:${serviceIdSegments.join('.')}');

  /// Parse a wire-format string (`'pluginId:serviceId'` or
  /// `'*:serviceId'`). Used by `RuntimeSettings.fromJson` and any code
  /// that round-trips Pins through external storage.
  ///
  /// Accepts any string at construction time; access to [pluginId] /
  /// [serviceId] re-validates and throws [FormatException] on malformed
  /// input.
  const Pin.fromWire(String wire) : _value = wire;

  /// The owning plugin id parsed from the underlying wire string.
  /// Wildcard wire (`'*:...'`) returns [PluginId.wildcard].
  ///
  /// Throws [FormatException] when the wire string has no `:` separator.
  PluginId get pluginId {
    final i = _value.indexOf(':');
    if (i <= 0) {
      throw FormatException('Pin "$_value" must be "pluginId:serviceId".');
    }
    final p = _value.substring(0, i);
    if (p == '*') return PluginId.wildcard;
    return PluginId(p);
  }

  /// The service id parsed from the underlying wire string.
  ///
  /// Throws [FormatException] when the wire string has no `:` separator
  /// or has nothing after it.
  ServiceId get serviceId {
    final i = _value.indexOf(':');
    if (i <= 0 || i == _value.length - 1) {
      throw FormatException('Pin "$_value" must be "pluginId:serviceId".');
    }
    return ServiceId(_value.substring(i + 1));
  }

  /// Whether this pin targets every plugin (wildcard) rather than a
  /// specific one. Equivalent to `pluginId == PluginId.wildcard` without
  /// re-parsing the wire string.
  bool get isWildcard {
    if (_value.length < 2) return false;
    // 0x2A = '*', 0x3A = ':'
    return _value.codeUnitAt(0) == 0x2A && _value.codeUnitAt(1) == 0x3A;
  }

  /// The canonical wire form. Identical to the underlying String
  /// representation; suitable for JSON keys.
  String get wire => _value;
}
