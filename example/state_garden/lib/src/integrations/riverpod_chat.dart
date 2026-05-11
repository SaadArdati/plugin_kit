import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// `Provider` injected by the host at app boot via
/// `sessionProvider.overrideWithValue(...)`. Resolving via override (not via
/// a `FutureProvider` that creates the session in `build`) avoids the
/// disposal-leak hazard documented in the research note: a `FutureProvider`
/// without `ref.onDispose(() => session.dispose())` leaks the previous
/// session when the provider invalidates.
final Provider<PluginSession> sessionProvider = Provider<PluginSession>((
  Ref ref,
) {
  throw UnimplementedError(
    'Override sessionProvider with the application session at app boot.',
  );
});

/// Recipe: Riverpod AsyncNotifier.
///
/// Subscribes inside [build]; registers `ref.onDispose` after subscribing so
/// the cancellation closure captures the current subscription. The Notifier
/// rebuilds when [sessionProvider] changes; both onDispose calls run in the
/// expected order, cancelling the old subscription before subscribing to
/// the new bus.
///
/// `_disposed` is reset to `false` at the top of every [build] on purpose:
/// each rebuild creates a fresh subscription whose [ref.onDispose] callback
/// flips the flag back to `true` when that subscription is cancelled. The
/// "provider swap tears down old subscription" widget test exercises the
/// rebuild path explicitly.
final AsyncNotifierProvider<ChatNotifier, List<ChatMessage>>
chatNotifierProvider = AsyncNotifierProvider<ChatNotifier, List<ChatMessage>>(
  ChatNotifier.new,
);

// #docregion riverpod-chat-chat-notifier
class ChatNotifier extends AsyncNotifier<List<ChatMessage>> {
  bool _disposed = false;

  @override
  Future<List<ChatMessage>> build() async {
    _disposed = false;
    final PluginSession session = ref.watch(sessionProvider);
    final StreamSubscription<void> sub = session.on<ChatMessagesChanged>(
      _onMessagesChanged,
    );
    ref.onDispose(() {
      _disposed = true;
      unawaited(sub.cancel());
    });
    return const <ChatMessage>[];
  }

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (_disposed) return;
    state = AsyncData<List<ChatMessage>>(envelope.event.messages);
  }

  Future<void> send(String text) async {
    final PluginSession session = ref.read(sessionProvider);
    await session.emit(SendMessageRequested(text));
  }
}
// #enddocregion riverpod-chat-chat-notifier

class RiverpodChatScreen extends ConsumerWidget {
  const RiverpodChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ChatMessage> messages =
        ref.watch(chatNotifierProvider).valueOrNull ?? const <ChatMessage>[];
    final ChatNotifier notifier = ref.read(chatNotifierProvider.notifier);
    return ChatView(
      title: 'Riverpod',
      messages: messages,
      onSend: notifier.send,
    );
  }
}
