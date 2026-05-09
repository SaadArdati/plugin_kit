import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// `BuildContext.watchEvent` / `BuildContext.readEvent` rely on this
/// widget being installed somewhere above the calling context.
/// `PluginSessionScope` installs it automatically; standalone uses can
/// instantiate it directly to expose a session's bus through the same
/// context extensions.
class PluginSessionEvents extends StatefulWidget {
  /// Wrap [child] in an event buffer keyed off [session]'s bus.
  const PluginSessionEvents({
    super.key,
    required this.session,
    required this.child,
  });

  /// The session whose bus this widget observes.
  final PluginSession session;

  /// The wrapped subtree.
  final Widget child;

  @override
  State<PluginSessionEvents> createState() => _PluginSessionEventsState();
}

class _PluginSessionEventsState extends State<PluginSessionEvents> {
  final Map<Type, Object?> _last = <Type, Object?>{};
  final Map<Type, StreamSubscription<void>> _subscriptions =
      <Type, StreamSubscription<void>>{};
  final Map<Type, int> _versions = <Type, int>{};
  int _tick = 0;

  @override
  void didUpdateWidget(PluginSessionEvents old) {
    super.didUpdateWidget(old);
    if (!identical(old.session, widget.session)) {
      _cancelAllSubscriptions();
      _last.clear();
      _versions.clear();
      _tick++;
    }
  }

  @override
  void dispose() {
    _cancelAllSubscriptions();
    super.dispose();
  }

  void _cancelAllSubscriptions() {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void ensureSubscribed<E>() {
    if (_subscriptions.containsKey(E)) return;
    _versions[E] = 0;
    _subscriptions[E] = widget.session.on<E>((envelope) {
      if (!mounted) return;
      setState(() {
        _last[E] = envelope.event;
        _versions[E] = (_versions[E] ?? 0) + 1;
        _tick++;
      });
    });
  }

  E? lastOf<E>() => _last[E] as E?;

  @override
  Widget build(BuildContext context) {
    return _PluginSessionEventsModel(
      state: this,
      tick: _tick,
      versions: Map<Type, int>.of(_versions),
      child: widget.child,
    );
  }
}

class _PluginSessionEventsModel extends InheritedModel<Type> {
  const _PluginSessionEventsModel({
    required this.state,
    required this.tick,
    required this.versions,
    required super.child,
  });

  final _PluginSessionEventsState state;
  final int tick;
  final Map<Type, int> versions;

  @override
  bool updateShouldNotify(_PluginSessionEventsModel old) => tick != old.tick;

  @override
  bool updateShouldNotifyDependent(
    _PluginSessionEventsModel old,
    Set<Type> aspects,
  ) {
    for (final type in aspects) {
      if ((versions[type] ?? 0) != (old.versions[type] ?? 0)) return true;
    }
    return false;
  }

  static _PluginSessionEventsState _stateOf(
    BuildContext context, {
    required bool listen,
    Type? aspect,
  }) {
    final model = listen
        ? InheritedModel.inheritFrom<_PluginSessionEventsModel>(
            context,
            aspect: aspect,
          )
        : context
                  .getElementForInheritedWidgetOfExactType<
                    _PluginSessionEventsModel
                  >()
                  ?.widget
              as _PluginSessionEventsModel?;
    if (model == null) {
      throw FlutterError(
        'BuildContext.watchEvent / readEvent called without an enclosing '
        'PluginSessionScope (or PluginSessionEvents) above it in the tree.\n'
        'Wrap the relevant subtree first.',
      );
    }
    return model.state;
  }
}

/// Convenience extensions for reading the most recent event of a given
/// type from the ambient [PluginSessionEvents] (installed by
/// `PluginSessionScope`).
extension PluginSessionEventsContextX on BuildContext {
  /// Returns the most recent envelope of type [E] observed on the
  /// ambient session, or `null` if no event of that type has fired
  /// since the scope was mounted.
  ///
  /// The calling element rebuilds when the next event of type [E]
  /// arrives. Other event types do not trigger rebuilds.
  ///
  /// Throws [FlutterError] when called outside a `PluginSessionScope`
  /// (or a manually-installed `PluginSessionEvents`).
  E? watchEvent<E>() {
    final state = _PluginSessionEventsModel._stateOf(
      this,
      listen: true,
      aspect: E,
    );
    state.ensureSubscribed<E>();
    return state.lastOf<E>();
  }

  /// Returns the most recent envelope of type [E] observed on the
  /// ambient session, without subscribing this element to future
  /// rebuilds. Use from one-shot call sites such as button callbacks.
  ///
  /// Calling [readEvent] still ensures a subscription exists for [E]
  /// at the scope level, so callers using both [watchEvent] and
  /// [readEvent] for the same type stay in sync.
  ///
  /// Throws [FlutterError] when called outside a `PluginSessionScope`
  /// (or a manually-installed `PluginSessionEvents`).
  E? readEvent<E>() {
    final state = _PluginSessionEventsModel._stateOf(this, listen: false);
    state.ensureSubscribed<E>();
    return state.lastOf<E>();
  }
}
