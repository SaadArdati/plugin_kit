import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

const ListEquality<ChatMessage> _messagesEquality = ListEquality<ChatMessage>();

/// Cubit state with structural equality on the message list and sending
/// flag.
// #docregion bloc-chat-chat-bloc-state
class ChatBlocState {
  const ChatBlocState({
    this.messages = const <ChatMessage>[],
    this.sending = false,
  });

  final List<ChatMessage> messages;
  final bool sending;

  ChatBlocState copyWith({List<ChatMessage>? messages, bool? sending}) {
    return ChatBlocState(
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatBlocState &&
          runtimeType == other.runtimeType &&
          sending == other.sending &&
          _messagesEquality.equals(messages, other.messages);

  @override
  int get hashCode => Object.hash(sending, _messagesEquality.hash(messages));
}
// #enddocregion bloc-chat-chat-bloc-state

/// Recipe: flutter_bloc Cubit.
// #docregion bloc-chat-chat-cubit
class ChatCubit extends Cubit<ChatBlocState> with PluginSessionListener {
  final PluginSession _session;

  @override
  PluginSession<SessionPluginContext> get session => _session;

  @override
  List<EventBinding> get subscriptions => [
    on<ChatMessagesChanged>(_onMessagesChanged),
  ];

  ChatCubit(this._session) : super(const ChatBlocState()) {
    attachSubscriptions();
  }

  Future<void> send(String text) async {
    if (isClosed) return;
    emit(state.copyWith(sending: true));
    await _session.emit(SendMessageRequested(text));
    if (isClosed) return;
    emit(state.copyWith(sending: false));
  }

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (isClosed) return;
    emit(state.copyWith(messages: envelope.event.messages));
  }

  @override
  Future<void> close() async {
    detachSubscriptions();
    return super.close();
  }
}
// #enddocregion bloc-chat-chat-cubit

class BlocChatScreen extends StatelessWidget {
  const BlocChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatCubit>(
      create: (_) => ChatCubit(session),
      child: const _BlocChatBody(),
    );
  }
}

class _BlocChatBody extends StatelessWidget {
  const _BlocChatBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatBlocState>(
      builder: (BuildContext context, ChatBlocState state) {
        return ChatView(
          title: 'Cubit',
          messages: state.messages,
          onSend: context.read<ChatCubit>().send,
        );
      },
    );
  }
}
