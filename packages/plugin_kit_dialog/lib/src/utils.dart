import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Signature for the dialog's save callback. Receives the current working
/// settings and may return a Future to delay dialog closure until async work
/// (persistence, validation, etc.) completes.
typedef SaveCallback = FutureOr<void> Function(RuntimeSettings);

/// Run [dispose] and route any error -- thrown synchronously from invoking
/// the closure, or surfacing on the returned future -- through
/// [FlutterError.reportError] tagged with `library: 'plugin_kit_dialog'`.
///
/// Used by widgets in this package whose `State.dispose` triggers an async
/// teardown path. Mirrors `disposeAndReport` from `flutter_plugin_kit` but
/// kept local so this package does not take a flutter_plugin_kit dependency.
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
          library: 'plugin_kit_dialog',
          context: ErrorDescription(contextDescription),
        ),
      );
    }),
  );
}
