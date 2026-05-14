import 'package:plugin_kit/src/typed_handles.dart';

/// Base class for "the request produced no answer" outcomes.
///
/// Sealed. The two concrete subtypes are [RequestNotWiredException]
/// (the consumer asked for a `(Request, Response)` type pair, or an
/// `identifier`-scoped variant of one, for which no handler is
/// registered) and [AllConcededException] (handlers ran but every one
/// returned `null` and `Response` is non-nullable).
///
/// [EventBus.maybeRequest] and [EventBus.maybeRequestSync] catch this
/// base type and convert it to a `null` return. Handler-thrown
/// exceptions are NOT subtypes of this class and are NOT caught by
/// `maybeRequest`; they propagate to the caller unchanged.
///
/// Callers that want to distinguish unwired-handler bugs from genuinely
/// conceded chains can catch the two subtypes separately:
///
/// ```dart
/// try {
///   final result = await bus.request<SearchQuery, SearchResults>(query);
/// } on RequestNotWiredException catch (e) {
///   log.severe('Search misconfigured: $e');
/// } on AllConcededException catch (e) {
///   log.info('No provider could answer this search; ${e.suggestion}');
/// }
/// ```
sealed class NoRequestAnswerException implements Exception {
  /// The `Request` type for which no answer was produced.
  Type get requestType;

  /// The `Response` type for which no answer was produced.
  Type get responseType;

  /// The identifier scoping the request, or null for unscoped requests.
  String? get identifier;
}

/// Thrown by [EventBus.request] / [EventBus.requestSync] when no handler
/// is registered for the `(Request, Response)` type pair, or no handler
/// matched the requested [identifier].
///
/// Almost always a wiring bug: the calling code expected a handler to
/// exist for this type pair (and identifier, if any), but the registry
/// has none. Fix by registering the handler with
/// [EventBus.onRequest] / [EventBus.onRequestSync].
class RequestNotWiredException extends NoRequestAnswerException {
  @override
  final Type requestType;
  @override
  final Type responseType;
  @override
  final String? identifier;

  /// True when the type pair has registrations but none matched the
  /// requested [identifier]. False when no registration exists for the
  /// type pair at all.
  final bool wasIdentifierMismatch;

  /// Creates a [RequestNotWiredException] for the given type pair.
  RequestNotWiredException({
    required this.requestType,
    required this.responseType,
    this.identifier,
    this.wasIdentifierMismatch = false,
  });

  @override
  String toString() {
    final id = identifier == null ? '' : ' (identifier: $identifier)';
    final detail = wasIdentifierMismatch
        ? 'handlers exist for this type pair but none matched the identifier'
        : 'no handler registered for this type pair';
    return 'RequestNotWiredException: $requestType -> $responseType$id: '
        '$detail. Register a handler with EventBus.onRequest before calling '
        'request/maybeRequest.';
  }
}

/// Thrown by [EventBus.request] / [EventBus.requestSync] when every
/// registered handler ran and returned `null` (conceded), and the
/// `Response` type is non-nullable.
///
/// This is not a bug per se: chains designed to allow concession may
/// legitimately bottom out when no handler can answer a given input.
/// However, treating "no one could answer" as an exception forces the
/// consumer to wrap normal flow in `try`/`catch`, which is rarely what
/// you want. If concession is a valid outcome at your call site, use
/// [EventBus.maybeRequest] / [EventBus.maybeRequestSync] instead: it
/// returns `null` for this case and propagates handler-thrown exceptions
/// unchanged.
///
/// Use [EventBus.request] only when you have asserted (by construction,
/// registration order, or domain invariant) that at least one handler
/// will claim. If that assertion ever breaks, this exception surfaces
/// the violation loudly.
class AllConcededException extends NoRequestAnswerException {
  @override
  final Type requestType;
  @override
  final Type responseType;
  @override
  final String? identifier;

  /// Creates an [AllConcededException] for the given type pair.
  AllConcededException({
    required this.requestType,
    required this.responseType,
    this.identifier,
  });

  /// The actionable suggestion this exception's message recommends.
  /// Exposed as a getter so tests can match on it without comparing
  /// the full message string.
  String get suggestion =>
      'Consider calling maybeRequest<$requestType, $responseType>(...) '
      'if concession is a valid outcome at this call site.';

  @override
  String toString() {
    final id = identifier == null ? '' : ' (identifier: $identifier)';
    return 'AllConcededException: $requestType -> $responseType$id: '
        'every registered handler conceded with null but Response is '
        'non-nullable. $suggestion';
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
