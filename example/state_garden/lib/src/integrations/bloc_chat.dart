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
/// flag. CRITICAL-10 of the architecture rules: exposed state types must
/// support value equality so observers do not rebuild on identical
/// snapshots.
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

/// Recipe: flutter_bloc Cubit.
///
/// Subscribes in the constructor; guards every emit (including the one in
/// the bus handler) with [isClosed]; cancels the subscription in [close].
/// The `if (isClosed) return` after every `await` corresponds to CRITICAL-2.
class ChatCubit extends Cubit<ChatBlocState> {
  ChatCubit(this._session) : super(const ChatBlocState()) {
    _subscription = _session.on<ChatMessagesChanged>(_onMessagesChanged);
  }

  final PluginSession _session;
  late final StreamSubscription<void> _subscription;

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
    await _subscription.cancel();
    return super.close();
  }
}

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
