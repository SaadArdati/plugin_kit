import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Reference recipe: `StatefulWidget` plus `setState`, no library.
///
/// The widget owns the [StreamSubscription]. Every async continuation that
/// touches state checks `mounted`. The subscription is cancelled in
/// [State.dispose].
class SetStateChatScreen extends StatefulWidget {
  const SetStateChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  State<SetStateChatScreen> createState() => _SetStateChatScreenState();
}

class _SetStateChatScreenState extends State<SetStateChatScreen> {
  StreamSubscription<void>? _subscription;
  List<ChatMessage> _messages = const <ChatMessage>[];

  @override
  void initState() {
    super.initState();
    _subscription = widget.session.on<ChatMessagesChanged>(_onMessagesChanged);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (!mounted) return;
    setState(() => _messages = envelope.event.messages);
  }

  Future<void> _onSubmit(String text) =>
      widget.session.emit(SendMessageRequested(text)).then((_) {});

  @override
  Widget build(BuildContext context) {
    return ChatView(title: 'setState', messages: _messages, onSend: _onSubmit);
  }
}
