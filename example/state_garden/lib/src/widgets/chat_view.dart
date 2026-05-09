import 'package:flutter/material.dart';

import '../chat/chat_message.dart';
import 'message_input.dart';
import 'message_list.dart';

/// Common scaffold used by every integration screen.
///
/// State-management screens build their bridge, then feed `messages` and
/// `onSend` into this widget. Uniform UX makes side-by-side proofs honest:
/// every test types into the same field key, taps the same button key, and
/// asserts against the same list key.
class ChatView extends StatelessWidget {
  const ChatView({
    super.key,
    required this.title,
    required this.messages,
    required this.onSend,
  });

  final String title;
  final List<ChatMessage> messages;
  final Future<void> Function(String text) onSend;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: <Widget>[
          Expanded(child: MessageList(messages: messages)),
          MessageInput(onSubmit: onSend),
        ],
      ),
    );
  }
}
