import 'package:plugin_kit/plugin_kit.dart';

import 'chat_events.dart';
import 'chat_message.dart';

/// Session-scoped chat service.
///
/// Subscribes to [SendMessageRequested] in [attach], appends the user line
/// and a synthetic bot reply to its message list, then emits
/// [ChatMessagesChanged] with the new snapshot. Each session constructs its
/// own service instance inline in [ChatPlugin.register], so message lists
/// never leak between sessions.
class ChatService extends StatefulPluginService {
  ChatService();

  final List<ChatMessage> _messages = <ChatMessage>[];

  /// Read-only view of accumulated messages. Test fixtures use this to
  /// verify per-session state isolation without going through the bus.
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Bot reply prefix. Subclasses override to differentiate concrete
  /// services for hot-swap proofs without rewriting the subscription wiring.
  String get replyPrefix => 'echo: ';

  @override
  void attach() {
    on<SendMessageRequested>(_handleSend);
  }

  Future<void> _handleSend(EventEnvelope<SendMessageRequested> envelope) async {
    _messages.add(ChatMessage(author: 'user', text: envelope.event.text));
    _messages.add(
      ChatMessage(author: 'bot', text: '$replyPrefix${envelope.event.text}'),
    );
    await emit(ChatMessagesChanged(List<ChatMessage>.of(_messages)));
  }
}

/// Higher-priority alternative used by the hot-swap test.
///
/// Replies with `'alt: '` instead of `'echo: '`. The override of [attach] is
/// intentionally a no-op: hot-swap exercises service resolution, not event
/// cascade. With both plugins enabled the base service handles events; this
/// service exists to be observed via [PluginSession.resolve].
class AltChatService extends ChatService {
  AltChatService();

  @override
  String get replyPrefix => 'alt: ';

  @override
  void attach() {
    // Intentional no-op. See class doc.
  }
}
