import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:provider/provider.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: `ChangeNotifier` plus `provider`.
///
/// The bridge stores its [StreamSubscription] in a final field. The handler
/// guards against a post-dispose fire by checking [_disposed], which the
/// override of [dispose] flips before cancelling the subscription. This
/// matters because `EventEnvelope` cascade can be mid-iteration when
/// cancel removes the entry: the snapshot the cascade is iterating still
/// contains the handler. Without the guard, [notifyListeners] would throw
/// after dispose.
class ChatChangeNotifier extends ChangeNotifier {
  ChatChangeNotifier(this._session) {
    _subscription = _session.on<ChatMessagesChanged>(_onMessagesChanged);
  }

  final PluginSession _session;
  late final StreamSubscription<void> _subscription;
  bool _disposed = false;

  List<ChatMessage> _messages = const <ChatMessage>[];
  List<ChatMessage> get messages => _messages;

  Future<void> send(String text) =>
      _session.emit(SendMessageRequested(text)).then((_) {});

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (_disposed) return;
    _messages = envelope.event.messages;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

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
