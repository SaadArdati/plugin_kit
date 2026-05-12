import 'package:plugin_kit/src/typed_handles.dart';

/// Why a `request` / `requestSync` call could not be fulfilled.
///
/// Carried by [RequestUnavailableException.reason]. Callers that need to
/// distinguish unavailability causes (e.g. log an "unregistered" path
/// differently from a "everyone conceded" path) switch on this enum
/// instead of parsing the human-readable message.
enum RequestUnavailableReason {
  /// No handler was registered for the `(Request, Response)` type pair
  /// at all. The request bucket itself was missing.
  noRegistration,

  /// The type pair has registered handlers, but the priority-merged set
  /// for the requested identifier is empty. Common shapes: a request
  /// made under an identifier no handler subscribes to, or an unscoped
  /// request when only identifier-scoped handlers exist.
  noMatchingHandler,

  /// At least one handler ran but every invocation returned null while
  /// the `Response` type is non-nullable. The cascade conceded without
  /// a winner.
  allConceded,
}

/// Exception thrown when a request cannot be fulfilled.
///
/// Thrown by [EventBus.request] and [EventBus.requestSync] for the three
/// availability cases enumerated by [RequestUnavailableReason]:
/// [RequestUnavailableReason.noRegistration],
/// [RequestUnavailableReason.noMatchingHandler], and
/// [RequestUnavailableReason.allConceded].
///
/// [EventBus.maybeRequest] and [EventBus.maybeRequestSync] catch this type
/// and convert it to a null return. Callers that need to distinguish
/// unavailability from a successful null response can catch it explicitly
/// and switch on [reason]:
///
/// ```dart
/// try {
///   final result = await bus.request<SearchQuery, SearchResults>(query);
/// } on RequestUnavailableException catch (e) {
///   final hint = switch (e.reason) {
///     RequestUnavailableReason.noRegistration => 'register a handler',
///     RequestUnavailableReason.noMatchingHandler => 'check identifier scope',
///     RequestUnavailableReason.allConceded => 'add a fallback handler',
///   };
///   log('Search unavailable (${e.reason.name}): $hint');
/// }
/// ```
class RequestUnavailableException implements Exception {
  /// The `Request` type for which no handler was available.
  final Type requestType;

  /// The `Response` type for which no handler was available.
  final Type responseType;

  /// The identifier scoping the request, or null for unscoped requests.
  final String? identifier;

  /// Why the request was unavailable. Switch on this for typed dispatch.
  final RequestUnavailableReason reason;

  /// Creates a [RequestUnavailableException] with the given [reason].
  const RequestUnavailableException({
    required this.requestType,
    required this.responseType,
    this.identifier,
    required this.reason,
  });

  /// Human-readable text derived from [reason].
  String get _reasonText => switch (reason) {
        RequestUnavailableReason.noRegistration =>
          'no handler registered for this type pair',
        RequestUnavailableReason.noMatchingHandler =>
          'no handler matched after priority merge',
        RequestUnavailableReason.allConceded =>
          'every registered handler conceded with null but Response is non-nullable',
      };

  @override
  String toString() {
    final id = identifier == null ? '' : ' (identifier: $identifier)';
    return 'RequestUnavailableException: $requestType -> $responseType$id: '
        '$_reasonText';
  }
}

/// Exception thrown when one or more plugins fail during a lifecycle phase.
///
/// During attach/detach loops, the runtime continues processing remaining
/// plugins even when one throws. After the loop, if any failures occurred,
/// this exception is thrown with all collected errors.
///
/// Example:
/// ```dart
/// try {
///   await runtime.init();
/// } on PluginLifecycleException catch (e) {
///   for (final (pluginId, error, stackTrace) in e.failures) {
///     print('Plugin $pluginId failed: $error');
///   }
/// }
/// ```
// #docregion exceptions-plugin-lifecycle-exception
class PluginLifecycleException implements Exception {
  /// The lifecycle phase where failures occurred (e.g. `'attachGlobal'`).
  final String phase;

  /// The list of plugin failures: `(pluginId, error, stackTrace)`.
  final List<(PluginId pluginId, Object error, StackTrace stackTrace)> failures;

  /// Creates a lifecycle exception for [phase] with collected [failures].
  PluginLifecycleException(
    this.phase,
    List<(PluginId, Object, StackTrace)> failures,
  ) : failures = List.unmodifiable(failures);

  @override
  String toString() {
    final buffer = StringBuffer(
      'PluginLifecycleException: ${failures.length} plugin(s) failed during $phase:\n',
    );
    for (final (pluginId, error, _) in failures) {
      buffer.writeln('  - $pluginId: $error');
    }
    return buffer.toString();
  }
}
// #enddocregion exceptions-plugin-lifecycle-exception

/// Aggregates multiple step failures within a single plugin's `attach` or
/// `detach` pass. Thrown only when more than one step (e.g. a service's
/// `attach()` AND the plugin's user `attach()`) raised during the same
/// `_runAttach` / `_runDetach` invocation.
///
/// When exactly one step fails, that step's original exception is rethrown
/// unchanged so consumers can pattern-match on its concrete type. When two
/// or more steps fail, this aggregate is rethrown so all original errors
/// are preserved together rather than only the first.
///
/// The runtime catches whichever exception bubbles up and stores it as one
/// entry in [PluginLifecycleException.failures]. To inspect the underlying
/// step failures, downcast that entry's `error` to this type.
class PluginStepAggregateException implements Exception {
  /// The plugin whose lifecycle pass produced these failures.
  final PluginId pluginId;

  /// Which framework-driven hook produced the failures: `'attach'` or
  /// `'detach'`.
  final String hook;

  /// Each entry is `(stepName, error, stackTrace)` for one failed step.
  /// Step names are framework-controlled and stable across renames /
  /// release-mode minification. The format is:
  ///
  /// - `'<serviceId>.attach'` / `'<serviceId>.detach'` for stateful service
  ///   user hooks (the service's registered [ServiceId] value).
  /// - `'<serviceId>.subscription.cancel'` /
  ///   `'<serviceId>.binding.cancel'` for failures inside a service's
  ///   `_unbindContext` cleanup.
  /// - `'<serviceId>.subscription.leak'` /
  ///   `'<serviceId>.binding.leak'` for re-entrant subscribe/bind calls
  ///   issued from inside a cancel callback during the service's
  ///   `_unbindContext`. The `error` is a [StateError]; the leaked entries
  ///   are dropped without being cancelled.
  /// - `'attach'` / `'detach'` for the plugin's own user hook.
  /// - `'subscription.cancel'` / `'binding.cancel'` (no `<serviceId>`
  ///   prefix) for failures cancelling subscriptions or bindings the
  ///   plugin owns directly via `Plugin.on(context, ...)` /
  ///   `Plugin.bind(context, ...)`.
  /// - `'subscription.leak'` / `'binding.leak'` (no `<serviceId>` prefix)
  ///   for the same re-entry misuse at the plugin level.
  ///
  /// Steps from the same plugin can repeat (e.g. two services failing
  /// `attach`), so this list is not keyed-set semantics.
  final List<(String step, Object error, StackTrace stackTrace)> stepFailures;

  /// Creates an aggregate for [pluginId]'s [hook] pass.
  PluginStepAggregateException(
    this.pluginId,
    this.hook,
    List<(String, Object, StackTrace)> stepFailures,
  ) : stepFailures = List.unmodifiable(stepFailures);

  @override
  String toString() {
    final buffer = StringBuffer(
      'PluginStepAggregateException: $pluginId $hook had '
      '${stepFailures.length} step failure(s):\n',
    );
    for (final (step, error, _) in stepFailures) {
      buffer.writeln('  - $step: $error');
    }
    return buffer.toString();
  }
}
