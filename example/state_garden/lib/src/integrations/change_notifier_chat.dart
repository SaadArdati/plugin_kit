import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:provider/provider.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: `ChangeNotifier` plus `provider`.
///
/// Mixes in [PluginSessionListener] so subscription lifecycle is declared
/// once via [subscriptions] and the mixin handles attach/cancel. The
/// post-dispose guard still matters because the cascade snapshot may
/// hold the handler when `cancel` runs mid-iteration: `notifyListeners`
/// must not fire after `dispose`.
// #docregion change-notifier-chat-chat-change-notifier
class ChatChangeNotifier extends ChangeNotifier with PluginSessionListener {
  ChatChangeNotifier(this._session) {
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

  List<ChatMessage> _messages = const <ChatMessage>[];

  List<ChatMessage> get messages => _messages;

  Future<void> send(String text) => _session.emit(SendMessageRequested(text));

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (_disposed) return;
    _messages = envelope.event.messages;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    detachSubscriptions();
    super.dispose();
  }
}
// #enddocregion change-notifier-chat-chat-change-notifier

/// Public screen widget. The host wraps it in a `ChangeNotifierProvider`
/// that constructs a [ChatChangeNotifier] from the supplied session.
class ChangeNotifierChatScreen extends StatelessWidget {
  const ChangeNotifierChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatChangeNotifier>(
      create: (_) => ChatChangeNotifier(session),
      child: const _ChangeNotifierChatBody(),
    );
  }
}

class _ChangeNotifierChatBody extends StatelessWidget {
  const _ChangeNotifierChatBody();

  @override
  Widget build(BuildContext context) {
    final ChatChangeNotifier bridge = context.watch<ChatChangeNotifier>();
    return ChatView(
      title: 'ChangeNotifier',
      messages: bridge.messages,
      onSend: bridge.send,
    );
  }
}
