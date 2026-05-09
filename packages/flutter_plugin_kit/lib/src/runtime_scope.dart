import 'package:flutter/widgets.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'dispose_reporter.dart';

/// Carries a [PluginRuntime] through the widget tree.
///
/// Two construction modes:
///
/// - Pass [runtime] to expose an already-constructed runtime. The scope
///   does not own its lifecycle; whoever created the runtime disposes it.
///   Equivalent to `Provider.value` for a runtime.
///
/// - Pass [plugins] (and optionally [initialSettings]) to let the scope
///   construct, [PluginRuntime.init], and [PluginRuntime.dispose]
///   the runtime itself. Convenient for simple apps where the scope's
///   lifetime matches the runtime's.
///
/// Exactly one of [runtime] or [plugins] must be supplied.
///
/// Descendants read the runtime via [PluginRuntimeScope.of] (throws if
/// missing) or [PluginRuntimeScope.maybeOf] (returns `null`).
class PluginRuntimeScope extends StatefulWidget {
  /// Wrap [child] with an externally-owned [runtime]. The scope will not
  /// dispose the runtime.
  const PluginRuntimeScope.value({
    super.key,
    required PluginRuntime this.runtime,
    required this.child,
  }) : plugins = null,
       initialSettings = null;

  /// Wrap [child] with a runtime built from [plugins]. The scope owns the
  /// runtime: it calls [PluginRuntime.init] in `initState` and
  /// [PluginRuntime.dispose] in `dispose`.
  const PluginRuntimeScope({
    super.key,
    required List<Plugin> this.plugins,
    this.initialSettings,
    required this.child,
  }) : runtime = null;

  /// Externally-owned runtime. Mutually exclusive with [plugins].
  final PluginRuntime? runtime;

  /// Plugins to register on a scope-owned runtime. Mutually exclusive
  /// with [runtime].
  final List<Plugin>? plugins;

  /// Optional initial settings applied during init when the scope owns
  /// the runtime.
  final RuntimeSettings? initialSettings;

  /// The wrapped subtree.
  final Widget child;

  /// Returns the runtime exposed by the nearest enclosing
  /// [PluginRuntimeScope]. Throws [FlutterError] if no scope is found.
  static PluginRuntime of(BuildContext context) {
    final runtime = maybeOf(context);
    if (runtime == null) {
      throw FlutterError(
        'PluginRuntimeScope.of() called with a context that does not contain '
        'a PluginRuntimeScope.\n'
        'Wrap the relevant subtree with PluginRuntimeScope before calling.',
      );
    }
    return runtime;
  }

  /// Returns the runtime exposed by the nearest enclosing
  /// [PluginRuntimeScope], or `null` if no scope is in the tree.
  static PluginRuntime? maybeOf(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_PluginRuntimeInherited>();
    return inherited?.runtime;
  }

  @override
  State<PluginRuntimeScope> createState() => _PluginRuntimeScopeState();
}

class _PluginRuntimeScopeState extends State<PluginRuntimeScope> {
  PluginRuntime? _ownedRuntime;

  PluginRuntime get _runtime => widget.runtime ?? _ownedRuntime!;

  @override
  void initState() {
    super.initState();
    if (widget.runtime == null) {
      final runtime = PluginRuntime(plugins: widget.plugins);
      runtime.init(settings: widget.initialSettings);
      _ownedRuntime = runtime;
    }
  }

  @override
  void dispose() {
    final runtime = _ownedRuntime;
    if (runtime != null) {
      disposeAndReport(
        runtime.dispose,
        contextDescription:
            'disposing owned PluginRuntime on PluginRuntimeScope unmount',
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PluginRuntimeInherited(runtime: _runtime, child: widget.child);
  }
}

class _PluginRuntimeInherited extends InheritedWidget {
  const _PluginRuntimeInherited({required this.runtime, required super.child});

  final PluginRuntime runtime;

  @override
  bool updateShouldNotify(_PluginRuntimeInherited old) =>
      !identical(runtime, old.runtime);
}
