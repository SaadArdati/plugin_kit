import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:get_it/get_it.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: GetIt as a session locator.
///
/// The host registers the active [PluginSession] into a [GetIt] instance at
/// app boot. The screen looks it up by type and feeds the result into
/// [PluginSessionStateListener] via the overridden `session` getter, so
/// the subscription mechanics (attach on mount, cancel on dispose, re-attach
/// on swap) come from the mixin. GetIt does not own the session lifecycle;
/// it is purely a resolution channel here.
///
/// What the recipe demonstrates: "service-locator-style session resolution."
/// What it does NOT demonstrate: a manual subscription baseline. For that,
/// see [SetStateChatScreen], which keeps every line of subscription
/// plumbing inline as the no-library reference.
class GetItChatScreen extends StatefulWidget {
  const GetItChatScreen({super.key, required this.locator});

  final GetIt locator;

  @override
  State<GetItChatScreen> createState() => _GetItChatScreenState();
}

class _GetItChatScreenState extends State<GetItChatScreen>
    with PluginSessionStateListener<GetItChatScreen> {
  late final PluginSession _session = widget.locator.get<PluginSession>();
  List<ChatMessage> _messages = const <ChatMessage>[];

  @override
  PluginSession? get session => _session;

  @override
  void initState() {
    super.initState();
    listen<ChatMessagesChanged>((envelope) {
      setState(() => _messages = envelope.event.messages);
    });
  }

  Future<void> _onSubmit(String text) =>
      _session.emit(SendMessageRequested(text)).then((_) {});

  @override
  Widget build(BuildContext context) {
    return ChatView(title: 'GetIt', messages: _messages, onSend: _onSubmit);
  }
}
