import 'dart:async';

import 'package:flutter/foundation.dart';

/// Fires a scope-owned `dispose()` and routes any error through
/// [FlutterError.reportError] instead of letting it escape as an uncaught
/// zone error.
///
/// Used internally by `PluginRuntimeScope` and `PluginSessionScope` for
/// every owned-resource teardown. The handler captures `Object`, not a
/// concrete type, so any exception thrown by the underlying `dispose()` —
/// `PluginLifecycleException`, `StateError`, anything else a plugin
/// raises — surfaces in `tester.takeException()` rather than disappearing.
///
/// Both sync and async throws are reported. [Future.sync] catches a
/// synchronous throw from invoking [dispose] and routes it through the
/// same `.catchError` chain as an async throw, so a `dispose()` whose
/// preconditions fail before it ever returns a Future does not escape
/// the helper. (This was the bug the helper was extracted to address;
/// without [Future.sync] the closure invocation could throw before
/// `.catchError` was attached.)
///
/// [contextDescription] is rendered as the `context` field of the
/// reported `FlutterErrorDetails` and lets the test failure (or production
/// log) name which dispose path produced the error: e.g. `'disposing
/// scope-owned PluginSession on PluginSessionScope swap'`.
void disposeAndReport(
  Future<void> Function() dispose, {
  required String contextDescription,
}) {
  unawaited(
    Future<void>.sync(dispose).catchError((Object e, StackTrace st) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'flutter_plugin_kit',
          context: ErrorDescription(contextDescription),
        ),
      );
    }),
  );
}
