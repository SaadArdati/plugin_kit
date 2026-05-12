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

  /// Builds an [EventBinding] that delivers the unwrapped event payload
  /// of type [E] to [handler] on each emission of an [E]-typed event.
  ///
  /// [priority] and [identifier] map directly to [EventBus.on].
  static EventBinding on<E>(
    void Function(E event) handler, {
    int priority = 0,
    String? identifier,
  }) => _OnBinding<E>(handler, priority: priority, identifier: identifier);
}

class _OnBinding<E> implements EventBinding {
  _OnBinding(this.handler, {this.priority = 0, this.identifier});

  final void Function(E event) handler;
  final int priority;
  final String? identifier;

  @override
  EventSubscription attachTo(PluginSession session) {
    return session.on<E>(
      (envelope) => handler(envelope.event),
      priority: priority,
      identifier: identifier,
    );
  }
}
