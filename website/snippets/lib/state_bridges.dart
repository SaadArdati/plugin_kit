/// Snippets for Provider/Riverpod/Bloc/setState state bridges.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// A chat message model.
class ChatMessage {
  /// The message author.
  final String author;

  /// The message text.
  final String text;

  /// Creates a [ChatMessage].
  const ChatMessage({required this.author, required this.text});
}

/// A command to send a new message.
class SendMessageRequested {
  /// The message text to send.
  final String text;

  /// Creates a [SendMessageRequested] command.
  const SendMessageRequested({required this.text});
}

/// An event emitted when the chat messages change.
class ChatMessagesChanged {
  /// The updated list of messages.
  final List<ChatMessage> messages;

  /// Creates a [ChatMessagesChanged] event.
  const ChatMessagesChanged({required this.messages});
}

/// Stub widget that renders a chat list and send box.
class ChatView extends StatelessWidget {
  /// Title shown in the header.
  final String title;

  /// The current list of messages.
  final List<ChatMessage> messages;

  /// Callback invoked when the user submits a message.
  final Future<void> Function(String text) onSend;

  /// Creates a [ChatView].
  const ChatView({
    super.key,
    required this.title,
    required this.messages,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(title),
        for (final m in messages) Text('${m.author}: ${m.text}'),
      ],
    );
  }
}

/// A chat screen widget that accepts an explicit session.
class SetStateChatScreen extends StatefulWidget {
  /// The plugin session providing chat events.
  final PluginSession session;

  /// Creates a [SetStateChatScreen].
  const SetStateChatScreen({super.key, required this.session});

  @override
  State<SetStateChatScreen> createState() => _SetStateChatScreenState();
}

// #docregion state-bridge-set-state
class _SetStateChatScreenState extends State<SetStateChatScreen>
    with PluginSessionStateListener<SetStateChatScreen> {
  @override
  PluginSession? get session => widget.session;

  List<ChatMessage> _messages = const <ChatMessage>[];

  @override
  void initState() {
    super.initState();
    listen<ChatMessagesChanged>((event) {
      if (!mounted) return;
      setState(() => _messages = event.messages);
    });
  }

  Future<void> _onSubmit(String text) =>
      widget.session.emit(SendMessageRequested(text: text));

  @override
  Widget build(BuildContext context) =>
      ChatView(title: 'setState', messages: _messages, onSend: _onSubmit);
}
// #enddocregion state-bridge-set-state

// #docregion state-bridge-event-notifier
/// Creates a ChangeNotifier backed by a session event stream.
PluginEventNotifier<ChatMessagesChanged> makeNotifier(PluginSession session) {
  return PluginEventNotifier<ChatMessagesChanged>(session);
}
// #enddocregion state-bridge-event-notifier

// #docregion state-bridge-chat-message-types
/// Standalone event types used in bridge examples.
void showChatTypes() {
  const msg = ChatMessage(author: 'user', text: 'hello');
  const changed = ChatMessagesChanged(messages: [msg]);
  const requested = SendMessageRequested(text: 'hello');

  print('${msg.author}: ${changed.messages.length} ${requested.text}');
}
// #enddocregion state-bridge-chat-message-types

// #docregion state-bridge-provider-notifier
/// Demonstrates PluginEventNotifier dropped into a ChangeNotifierProvider.
Widget buildChangeNotifierProviderExample(PluginSession session) {
  return ListenableBuilder(
    listenable: PluginEventNotifier<ChatMessagesChanged>(session),
    builder: (context, notifier) {
      final messages =
          (notifier as PluginEventNotifier<ChatMessagesChanged>).value?.messages ??
              const <ChatMessage>[];
      return ChatView(
        title: 'notifier',
        messages: messages,
        onSend: (text) => session.emit(SendMessageRequested(text: text)),
      );
    },
  );
}
// #enddocregion state-bridge-provider-notifier

// #docregion state-bridge-get-it-screen
/// Screen that reads its session from an injected locator-style holder.
///
/// In GetIt usage, swap [locatorGet] for [GetIt.I.get<PluginSession>()].
/// This snippet avoids the GetIt import so it compiles without the package.
class GetItChatScreen extends StatefulWidget {
  /// Returns the active session from the service locator.
  final PluginSession Function() locatorGet;

  /// Creates a [GetItChatScreen] backed by [locatorGet].
  const GetItChatScreen({super.key, required this.locatorGet});

  @override
  State<GetItChatScreen> createState() => _GetItChatScreenState();
}

class _GetItChatScreenState extends State<GetItChatScreen> {
  late final PluginSession _session;
  StreamSubscription<void>? _subscription;
  List<ChatMessage> _messages = const <ChatMessage>[];

  @override
  void initState() {
    super.initState();
    _session = widget.locatorGet();
    _subscription = _session.on<ChatMessagesChanged>((envelope) {
      if (!mounted) return;
      setState(() => _messages = envelope.event.messages);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatView(
        title: 'GetIt',
        messages: _messages,
        onSend: (text) => _session.emit(SendMessageRequested(text: text)),
      );
}
// #enddocregion state-bridge-get-it-screen
