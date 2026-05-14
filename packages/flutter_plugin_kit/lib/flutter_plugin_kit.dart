/// Flutter ergonomics on top of `plugin_kit`.
///
/// Provides:
///
/// - [PluginRuntimeScope] / [PluginSessionScope]: `StatefulWidget`s that
///   provide inherited scopes carrying a `PluginRuntime` / `PluginSession`.
/// - [PluginSessionStateListener]: a `State` mixin that subscribes to
///   session bus events using portable [EventBinding] descriptors and
///   re-attaches automatically across session swaps.
/// - [PluginEventNotifier]: a `ChangeNotifier` / `ValueListenable<E?>`
///   that exposes the most recent event of type `E` on a session, so it
///   plugs straight into `provider`'s `ChangeNotifierProvider` or any
///   other consumer of the foundation `Listenable` interface.
/// - `BuildContext.watchEvent<E>()` and `BuildContext.readEvent<E>()`:
///   convenience extensions for callers without an external state library.
/// - [disposeAndReport]: runs an async dispose and routes any sync OR
///   async throw through `FlutterError.reportError` instead of letting it
///   escape as an uncaught zone error. The same helper used internally by
///   the scopes; exposed for any custom widget whose `State.dispose` fires
///   off a similar async teardown.
///
/// This package depends only on `flutter` and `plugin_kit`. It uses
/// standard Flutter `ChangeNotifier` / `ValueListenable` interfaces and
/// `InheritedModel`, so it interoperates with `provider`, `flutter_bloc`,
/// `riverpod`, etc. without taking a direct dependency on any of them.
library;

export 'src/dispose_reporter.dart';
export 'src/event_notifier.dart';
export 'src/runtime_scope.dart';
export 'src/session_events.dart'
    show PluginSessionEvents, PluginSessionEventsContextX;
export 'src/session_listener.dart';
export 'src/session_scope.dart';
