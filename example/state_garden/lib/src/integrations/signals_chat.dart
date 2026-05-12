import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: signals_flutter.
///
/// One [Signal] holds the snapshot. The bus handler writes to
/// `messages.value`; the [Watch] builder rebuilds on read tracking.
/// Mixes in [PluginSessionListener] for declarative subscription
/// lifecycle; the `_disposed` guard still blocks any in-flight cascade
/// fire after dispose.
// #docregion signals-chat-signals-chat-bridge
class SignalsChatBridge with PluginSessionListener {
  SignalsChatBridge(this._session) {
    attachSubscriptions();
  }

  final PluginSession _session;

  @override
  PluginSession get session => _session;

  @override
  List<EventBinding> get subscriptions => [
    on<ChatMessagesChanged>(_onMessagesChanged),
  ];

  bool _disposed = false;

  final Signal<List<ChatMessage>> messages = signal(const <ChatMessage>[]);

  Future<void> send(String text) =>
      _session.emit(SendMessageRequested(text)).then((_) {});

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (_disposed) return;
    messages.value = envelope.event.messages;
  }

  void dispose() {
    _disposed = true;
    detachSubscriptions();
  }
}
// #enddocregion signals-chat-signals-chat-bridge

class SignalsChatScreen extends StatefulWidget {
  const SignalsChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  State<SignalsChatScreen> createState() => _SignalsChatScreenState();
}

class _SignalsChatScreenState extends State<SignalsChatScreen> {
  late final SignalsChatBridge _bridge = SignalsChatBridge(widget.session);

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Watch(
      (BuildContext context) => ChatView(
        title: 'signals_flutter',
        messages: _bridge.messages.value,
        onSend: _bridge.send,
      ),
    );
  }
}
