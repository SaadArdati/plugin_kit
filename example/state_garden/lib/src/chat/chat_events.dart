import 'chat_message.dart';

/// Intent event: the host (a state holder, a button callback, a test) asks
/// the plugin to handle a new user message. Final fields because this is a
/// command, not a draft to mutate.
class SendMessageRequested {
  const SendMessageRequested(this.text);
  final String text;
}

/// Fact event: emitted by the chat plugin after appending the user line and
/// the bot line. Carries the full snapshot of the message list so consumers
/// can replace state in one assignment without merging deltas.
class ChatMessagesChanged {
  const ChatMessagesChanged(this.messages);
  final List<ChatMessage> messages;
}
