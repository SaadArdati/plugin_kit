import 'package:flutter/widgets.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'dispose_reporter.dart';

/// Carries a [PluginRuntimeManager] through the widget tree.
///
/// Two construction modes:
///
/// - Pass [runtime] to expose an already-constructed manager. The scope
///   does not own its lifecycle; whoever created the manager disposes it.
///   Equivalent to `Provider.value` for a runtime.
///
/// - Pass [plugins] (and optionally [initialSettings]) to let the scope
///   construct, [PluginRuntimeManager.init], and [PluginRuntimeManager.dispose]
///   the manager itself. Convenient for simple apps where the scope's
///   lifetime matches the runtime's.
///
/// Exactly one of [runtime] or [plugins] must be supplied.
///
/// Descendants read the manager via [PluginRuntimeScope.of] (throws if
/// missing) or [PluginRuntimeScope.maybeOf] (returns `null`).
class PluginRuntimeScope extends StatefulWidget {
  /// Wrap [child] with an externally-owned [runtime]. The scope will not
  /// dispose the manager.
  const PluginRuntimeScope.value({
    super.key,
    required PluginRuntimeManager this.runtime,
    required this.child,
  }) : plugins = null,
       initialSettings = null;

  /// Wrap [child] with a manager built from [plugins]. The scope owns the
  /// manager: it calls [PluginRuntimeManager.init] in `initState` and
  /// [PluginRuntimeManager.dispose] in `dispose`.
  const PluginRuntimeScope({
    super.key,
    required List<Plugin> this.plugins,
    this.initialSettings,
    required this.child,
  }) : runtime = null;

  /// Externally-owned manager. Mutually exclusive with [plugins].
  final PluginRuntimeManager? runtime;

  /// Plugins to register on a scope-owned manager. Mutually exclusive
  /// with [runtime].
  final List<Plugin>? plugins;

  /// Optional initial settings applied during init when the scope owns
  /// the manager.
  final RuntimeSettings? initialSettings;

  /// The wrapped subtree.
  final Widget child;

  /// Returns the manager exposed by the nearest enclosing
  /// [PluginRuntimeScope]. Throws [FlutterError] if no scope is found.
  static PluginRuntimeManager of(BuildContext context) {
    final manager = maybeOf(context);
    if (manager == null) {
      throw FlutterError(
        'PluginRuntimeScope.of() called with a context that does not contain '
        'a PluginRuntimeScope.\n'
        'Wrap the relevant subtree with PluginRuntimeScope before calling.',
      );
    }
    return manager;
  }

  /// Returns the manager exposed by the nearest enclosing
  /// [PluginRuntimeScope], or `null` if no scope is in the tree.
  static PluginRuntimeManager? maybeOf(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_PluginRuntimeInherited>();
    return inherited?.manager;
  }

  @override
  State<PluginRuntimeScope> createState() => _PluginRuntimeScopeState();
}

class _PluginRuntimeScopeState extends State<PluginRuntimeScope> {
  PluginRuntimeManager? _ownedManager;

  PluginRuntimeManager get _manager => widget.runtime ?? _ownedManager!;

  @override
  void initState() {
    super.initState();
    if (widget.runtime == null) {
      final manager = PluginRuntimeManager(plugins: widget.plugins);
      manager.init(initialSettings: widget.initialSettings);
      _ownedManager = manager;
    }
  }

  @override
  void dispose() {
    final manager = _ownedManager;
    if (manager != null) {
      disposeAndReport(
        manager.dispose,
        contextDescription:
            'disposing owned PluginRuntimeManager on PluginRuntimeScope unmount',
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PluginRuntimeInherited(manager: _manager, child: widget.child);
  }
}

class _PluginRuntimeInherited extends InheritedWidget {
  const _PluginRuntimeInherited({required this.manager, required super.child});

  final PluginRuntimeManager manager;

  @override
  bool updateShouldNotify(_PluginRuntimeInherited old) =>
      !identical(manager, old.manager);
}
