import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: MobX without code generation.
///
/// One [Observable] holds the snapshot, mutated inside [runInAction] so the
/// reaction system observes the change atomically. The [Observer] widget
/// re-runs `build` when the observable is read inside it. Cancels the bus
/// subscription in [dispose]; the `_disposed` guard blocks any in-flight
/// cascade fire after dispose.
// #docregion mobx-chat-mobx-chat-bridge
class MobxChatBridge {
  MobxChatBridge(this._session) {
    _subscription = _session.on<ChatMessagesChanged>(_onMessagesChanged);
  }

  final PluginSession _session;
  late final StreamSubscription<void> _subscription;
  bool _disposed = false;

  final Observable<List<ChatMessage>> messages = Observable<List<ChatMessage>>(
    const <ChatMessage>[],
  );

  Future<void> send(String text) =>
      _session.emit(SendMessageRequested(text)).then((_) {});

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (_disposed) return;
    runInAction(() => messages.value = envelope.event.messages);
  }

  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
  }
}
// #enddocregion mobx-chat-mobx-chat-bridge

class MobxChatScreen extends StatefulWidget {
  const MobxChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  State<MobxChatScreen> createState() => _MobxChatScreenState();
}

class _MobxChatScreenState extends State<MobxChatScreen> {
  late final MobxChatBridge _bridge = MobxChatBridge(widget.session);

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (BuildContext context) => ChatView(
        title: 'MobX',
        messages: _bridge.messages.value,
        onSend: _bridge.send,
      ),
    );
  }
}
