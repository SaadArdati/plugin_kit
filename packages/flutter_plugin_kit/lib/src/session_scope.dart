import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'dispose_reporter.dart';
import 'runtime_scope.dart';
import 'session_events.dart';

/// Carries a [PluginSession] through the widget tree and installs the
/// internal event buffer that powers `BuildContext.watchEvent` /
/// `readEvent`.
///
/// Three resolution modes, from most explicit to least:
///
/// - Pass [session] to expose an externally-owned session. The scope
///   does not own its lifecycle; the caller disposes it.
/// - Pass [runtime] (without [session]) to let the scope call
///   [PluginRuntimeManager.createSession] and dispose the resulting
///   session when the widget unmounts.
/// - Pass neither: the scope reads [PluginRuntimeManager] from the
///   nearest enclosing [PluginRuntimeScope] and creates and owns a
///   session from it.
///
/// Session creation is asynchronous. While the future is pending, the
/// optional [loading] builder is rendered (default: a centred
/// [CircularProgressIndicator]). If creation throws, [error] is rendered
/// (default: [ErrorWidget]).
///
/// Descendants read the session via [PluginSessionScope.of] (throws if
/// missing) or [PluginSessionScope.maybeOf] (returns `null`).
class PluginSessionScope extends StatefulWidget {
  /// Creates a session scope. At most one of [session] or [runtime] may
  /// be supplied; with neither, the scope falls back to the ambient
  /// [PluginRuntimeScope]. The assertion in the initializer list catches
  /// the misconfiguration in debug mode — supplying both would otherwise
  /// silently prefer [session], which is rarely what the caller intends.
  const PluginSessionScope({
    super.key,
    this.session,
    this.runtime,
    this.loading,
    this.error,
    required this.child,
  }) : assert(
         session == null || runtime == null,
         'PluginSessionScope must not receive both `session` and `runtime`. '
         'Supply `session` for an externally-owned session, OR `runtime` for '
         'auto-create against an explicit runtime, OR neither to fall back '
         'to the ambient PluginRuntimeScope. (A future release will split '
         'these into named constructors.)',
       );

  /// External session to expose. If provided, the scope does not create
  /// or dispose; lifecycle is the caller's responsibility.
  final PluginSession? session;

  /// Runtime to call [PluginRuntimeManager.createSession] on. Used only
  /// when [session] is null. The scope does not dispose [runtime].
  final PluginRuntimeManager? runtime;

  /// Widget to display while [PluginRuntimeManager.createSession] is in
  /// flight. Defaults to a centred [CircularProgressIndicator].
  final WidgetBuilder? loading;

  /// Builder invoked when session creation throws. Defaults to
  /// [ErrorWidget] over the error.
  final Widget Function(BuildContext context, Object error)? error;

  /// The wrapped subtree. Children may call [PluginSessionScope.of] or
  /// `BuildContext.watchEvent` / `readEvent`.
  final Widget child;

  /// Returns the session exposed by the nearest enclosing
  /// [PluginSessionScope]. Throws [FlutterError] if no scope is in the
  /// tree, or if the scope is still resolving its session.
  static PluginSession of(BuildContext context) {
    final session = maybeOf(context);
    if (session == null) {
      throw FlutterError(
        'PluginSessionScope.of() called with a context that does not contain '
        'a ready PluginSessionScope.\n'
        'Either no PluginSessionScope ancestor exists, or the scope has not '
        'finished creating its session yet.',
      );
    }
    return session;
  }

  /// Returns the session exposed by the nearest enclosing
  /// [PluginSessionScope], or `null` if no scope is in the tree or the
  /// scope is still resolving.
  static PluginSession? maybeOf(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_PluginSessionInherited>();
    return inherited?.session;
  }

  @override
  State<PluginSessionScope> createState() => _PluginSessionScopeState();
}

class _PluginSessionScopeState extends State<PluginSessionScope> {
  PluginSession? _session;
  bool _ownsSession = false;
  Object? _error;
  bool _creationStarted = false;
  int _creationGen = 0;
  PluginRuntimeManager? _activeManager;

  @override
  void initState() {
    super.initState();
    if (widget.session != null) {
      _session = widget.session;
      _ownsSession = false;
    } else {
      _ownsSession = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Detect ambient runtime swap when in auto-create mode without an
    // explicit widget.runtime: the ambient PluginRuntimeScope changed
    // its manager. The dependency on _PluginRuntimeInherited fires
    // didChangeDependencies; we re-create the session from the new manager.
    if (widget.session == null && widget.runtime == null) {
      final ambient = PluginRuntimeScope.maybeOf(context);
      if (_activeManager != null &&
          ambient != null &&
          !identical(ambient, _activeManager)) {
        _creationGen++;
        if (_ownsSession && _session != null) {
          disposeAndReport(
            _session!.dispose,
            contextDescription:
                'disposing PluginSession after ambient runtime swap',
          );
        }
        _session = null;
        _ownsSession = true;
        _error = null;
        _creationStarted = false;
      }
    }
    _maybeStartCreation();
  }

  @override
  void didUpdateWidget(PluginSessionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = !identical(widget.session, oldWidget.session);
    final runtimeChangedInAutoMode =
        widget.session == null && !identical(widget.runtime, oldWidget.runtime);

    if (sessionChanged || runtimeChangedInAutoMode) {
      _creationGen++;

      if (_ownsSession &&
          _session != null &&
          !identical(_session, widget.session)) {
        disposeAndReport(
          _session!.dispose,
          contextDescription:
              'disposing replaced PluginSession in PluginSessionScope.didUpdateWidget',
        );
      }

      _session = widget.session;
      _ownsSession = widget.session == null;
      _error = null;
      _creationStarted = false;

      _maybeStartCreation();
    }
  }

  void _maybeStartCreation() {
    if (_creationStarted) return;
    if (_session != null) return;
    if (_error != null) return;
    if (!_ownsSession) return;
    _creationStarted = true;
    _createSession();
  }

  Future<void> _createSession() async {
    final gen = _creationGen;
    final PluginRuntimeManager manager;
    try {
      manager = widget.runtime ?? PluginRuntimeScope.of(context);
    } catch (error) {
      if (!mounted) return;
      if (_creationGen != gen) return;
      setState(() => _error = error);
      return;
    }
    _activeManager = manager;
    try {
      final session = await manager.createSession();
      if (!mounted) {
        disposeAndReport(
          session.dispose,
          contextDescription: 'disposing stale auto-created PluginSession',
        );
        return;
      }
      // Stale completion: a swap happened during the await. Drop this
      // session without exposing it.
      if (_creationGen != gen) {
        disposeAndReport(
          session.dispose,
          contextDescription: 'disposing stale auto-created PluginSession',
        );
        return;
      }
      setState(() => _session = session);
    } catch (error) {
      if (!mounted) return;
      if (_creationGen != gen) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    if (_ownsSession) {
      final s = _session;
      if (s != null) {
        disposeAndReport(
          s.dispose,
          contextDescription:
              'disposing owned PluginSession on PluginSessionScope unmount',
        );
      }
    }
    _activeManager = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final builder = widget.error;
      if (builder != null) return builder(context, _error!);
      return ErrorWidget(_error!);
    }
    final session = _session;
    if (session == null) {
      final builder = widget.loading;
      if (builder != null) return builder(context);
      return const Center(child: CircularProgressIndicator());
    }
    return _PluginSessionInherited(
      session: session,
      child: PluginSessionEvents(session: session, child: widget.child),
    );
  }
}

class _PluginSessionInherited extends InheritedWidget {
  const _PluginSessionInherited({required this.session, required super.child});

  final PluginSession session;

  @override
  bool updateShouldNotify(_PluginSessionInherited old) =>
      !identical(session, old.session);
}
