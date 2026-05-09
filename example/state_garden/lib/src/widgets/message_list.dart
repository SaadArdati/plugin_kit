import 'package:flutter/material.dart';

import '../chat/chat_message.dart';

/// Renders a vertical list of [ChatMessage]s.
///
/// Pure presentation: no plugin_kit dependency, no subscription. Widget tests
/// look up the list via the `messages_list` key.
class MessageList extends StatelessWidget {
  const MessageList({super.key, required this.messages});

  final List<ChatMessage> messages;

  static const Key listKey = Key('messages_list');

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: listKey,
      itemCount: messages.length,
      itemBuilder: (BuildContext context, int index) {
        final ChatMessage message = messages[index];
        return ListTile(
          title: Text(message.text),
          subtitle: Text(message.author),
        );
      },
    );
  }
}
