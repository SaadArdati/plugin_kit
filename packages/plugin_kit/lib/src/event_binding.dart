import 'package:plugin_kit/plugin_kit.dart';

/// Portable descriptor of "subscribe to events of type [E] on a session."
///
/// `EventBinding` does not own a subscription; it only knows how to create
/// one against a [PluginSession]. A host (a session-aware controller, the
/// Flutter `PluginSessionStateListener` State mixin in
/// `package:flutter_plugin_kit`, or any custom orchestrator) calls
/// [attachTo] to materialize the subscription and is responsible for
/// cancelling it.
///
/// Use [EventBinding.on] to build the standard binding kind. Custom
/// binding kinds may implement this interface directly.
abstract class EventBinding {
  /// Materializes a subscription against [session] and returns it.
  ///
  /// The caller is responsible for cancelling the returned subscription
  /// when the observer is no longer needed.
  EventSubscription attachTo(PluginSession session);

  /// Builds an [EventBinding] that delivers the full [EventEnvelope] of
  /// type [E] to [handler] on each emission of an [E]-typed event.
  ///
  /// The handler receives the envelope (not the unwrapped event) so
  /// envelope context like `identifier` and `stopped` stays reachable.
  /// Use `envelope.event` for the payload. The shape matches
  /// [EventBus.on] / [PluginSession.on], so callers can move between the
  /// declarative and imperative APIs without re-typing handlers.
  ///
  /// [priority] and [identifier] map directly to [EventBus.on].
  static EventBinding on<E>(
    void Function(EventEnvelope<E> envelope) handler, {
    int priority = 0,
    String? identifier,
  }) => _OnBinding<E>(handler, priority: priority, identifier: identifier);
}

class _OnBinding<E> implements EventBinding {
  _OnBinding(this.handler, {this.priority = 0, this.identifier});

  final void Function(EventEnvelope<E> envelope) handler;
  final int priority;
  final String? identifier;

  @override
  EventSubscription attachTo(PluginSession session) {
    return session.on<E>(handler, priority: priority, identifier: identifier);
  }
}
