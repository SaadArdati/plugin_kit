import 'package:flutter/foundation.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// A [ChangeNotifier] that exposes the most recent event of type [E]
/// observed on a [PluginSession] bus.
///
/// Implements [ValueListenable] so it composes with any consumer of the
/// foundation listenable interface — `ChangeNotifierProvider`,
/// `ValueListenableBuilder`, `ValueListenableProvider`, custom
/// state-management glue. This package never imports a specific state
/// library; the `Listenable` shape is the integration point.
///
/// ```dart
/// final notifier = PluginEventNotifier<ChatMessagesChanged>(session);
/// // Drop into provider:
/// ChangeNotifierProvider.value(value: notifier, child: ...);
/// // Or read directly:
/// ValueListenableBuilder<ChatMessagesChanged?>(
///   valueListenable: notifier,
///   builder: (context, last, _) => ...,
/// );
/// ```
///
/// The notifier subscribes to [PluginSession.on] for [E] in its
/// constructor and cancels in [dispose]. [value] is `null` until the
/// first event of type [E] arrives.
///
/// Optional [priority] and [identifier] are forwarded to [EventBus.on].
class PluginEventNotifier<E> extends ChangeNotifier
    implements ValueListenable<E?> {
  /// Subscribe to [E] events on [session]. The notifier owns its
  /// subscription and cancels it in [dispose].
  PluginEventNotifier(
    PluginSession session, {
    int priority = 0,
    String? identifier,
  }) {
    _subscription = session.on<E>(
      (envelope) {
        _value = envelope.event;
        notifyListeners();
      },
      priority: priority,
      identifier: identifier,
    );
  }

  late final EventSubscription _subscription;
  E? _value;

  /// The most recent [E] envelope observed on the session, or `null` if
  /// no event of type [E] has been received yet.
  @override
  E? get value => _value;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
