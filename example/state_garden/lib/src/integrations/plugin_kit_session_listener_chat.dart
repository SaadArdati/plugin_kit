import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:provider/provider.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: pure-Dart `PluginSessionListener` mixin (from `package:plugin_kit`).
///
/// Same shape as the [ChangeNotifier]-plus-provider recipe in
/// `change_notifier_chat.dart`, but the bridge mixes in
/// [PluginSessionListener] and supplies its bindings declaratively through
/// the [subscriptions] getter. The mixin owns the [StreamSubscription]
/// list, [attachSubscriptions] / [detachSubscriptions] are idempotent, and
/// the host does not store a `_disposed` flag because dispose runs detach
/// before `notifyListeners` could fire from a late envelope.
///
/// Use this mixin when the host is a pure-Dart object (cubit, controller,
/// `ChangeNotifier`) that owns its session for its full lifetime. For a
/// `State<W>` subscribing to an ambient session, prefer
/// `PluginSessionStateListener` from `package:flutter_plugin_kit` — it
/// re-attaches across session swaps automatically and ties cancellation
/// to the State's dispose.
class ChatSessionListenerNotifier extends ChangeNotifier
    with PluginSessionListener {
  ChatSessionListenerNotifier(this._session) {
    attachSubscriptions();
  }

  final PluginSession _session;

  @override
  PluginSession get session => _session;

  @override
  List<EventBinding> get subscriptions => [
    EventBinding.on<ChatMessagesChanged>(_onMessagesChanged),
  ];

  List<ChatMessage> _messages = const <ChatMessage>[];
  List<ChatMessage> get messages => _messages;

  Future<void> send(String text) =>
      _session.emit(SendMessageRequested(text)).then((_) {});

  void _onMessagesChanged(ChatMessagesChanged event) {
    _messages = event.messages;
    notifyListeners();
  }

  @override
  void dispose() {
    detachSubscriptions();
    super.dispose();
  }
}

/// Public screen widget. The host wraps it in a `ChangeNotifierProvider`
/// that constructs a [ChatSessionListenerNotifier] from the supplied
/// session.
class PluginSessionListenerChatScreen extends StatelessWidget {
  const PluginSessionListenerChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ChatSessionListenerNotifier>(
      create: (_) => ChatSessionListenerNotifier(session),
      child: const _PluginSessionListenerChatBody(),
    );
  }
}

class _PluginSessionListenerChatBody extends StatelessWidget {
  const _PluginSessionListenerChatBody();

  @override
  Widget build(BuildContext context) {
    final ChatSessionListenerNotifier bridge = context
        .watch<ChatSessionListenerNotifier>();
    return ChatView(
      title: 'plugin_kit (PluginSessionListener mixin)',
      messages: bridge.messages,
      onSend: bridge.send,
    );
  }
}
