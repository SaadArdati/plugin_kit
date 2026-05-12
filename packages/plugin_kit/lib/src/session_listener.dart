library;

import 'package:plugin_kit/plugin_kit.dart';

/// Declarative session-event listener mixin for pure-Dart hosts (cubits,
/// controllers, services). The host supplies the [session] it listens to
/// and the list of [subscriptions] (a `List<EventBinding>`) it wants
/// attached. The mixin materializes them through [attachSubscriptions] and
/// cancels them through [detachSubscriptions], both idempotent.
///
/// Different shape from the Flutter sibling. Despite the similar name,
/// this mixin is *not* a pure-Dart mirror of `PluginSessionStateListener`
/// in `package:flutter_plugin_kit`. The Flutter mixin exposes an
/// imperative `listen<E>(handler)` API tied to a `State<W>` lifecycle;
/// this one exposes a declarative `subscriptions` getter tied to
/// host-driven attach/detach calls. They share `EventBinding` as the
/// underlying descriptor type but the call sites do not look the same.
/// Pick the shape that matches your host: a `State` reaches for the
/// Flutter mixin; a Cubit / `ChangeNotifier` / plain controller reaches
/// for this one.
///
/// `session` is synchronous and non-null. If the host needs to follow a
/// session that changes mid-life, it owns the orchestration: call
/// [detachSubscriptions], swap its internal session reference, call
/// [attachSubscriptions] again. The mixin does not model swap on its own
/// because the typical pure-Dart pattern is "scope the host to one
/// session and recreate it on swap" rather than mid-life rebinding.
mixin PluginSessionListener {
  /// The session the host wants its bindings attached to. Read once per
  /// call to [attachSubscriptions]; not observed for changes.
  PluginSession get session;

  /// The bindings the host wants attached. Read once per call to
  /// [attachSubscriptions]; updates between attaches are picked up on
  /// the next attach.
  List<EventBinding> get subscriptions;

  final List<EventSubscription> _eventSubs = [];
  bool _attached = false;

  /// Attach all [subscriptions] to [session]. No-op if already attached.
  void attachSubscriptions() {
    if (_attached) return;
    _attached = true;
    for (final binding in subscriptions) {
      _eventSubs.add(binding.attachTo(session));
    }
  }

  /// Cancel every active subscription. No-op if not attached.
  void detachSubscriptions() {
    if (!_attached) return;
    _attached = false;
    for (final sub in _eventSubs) {
      sub.cancel();
    }
    _eventSubs.clear();
  }

  /// Helper to build a standard [EventBinding] for the given handler and
  /// parameters. Use this in the [subscriptions] getter to keep it concise.
  /// For advanced usage, use [EventBinding] directly.
  ///
  /// The handler receives the full [EventEnvelope] so envelope metadata
  /// (`sourcePluginId`, `timestamp`, `sequence`) stays reachable. Read
  /// the payload via `envelope.event`.
  EventBinding on<E>(
    void Function(EventEnvelope<E> envelope) handler, {
    int priority = 0,
    String? identifier,
  }) => EventBinding.on(handler, priority: priority, identifier: identifier);
}
