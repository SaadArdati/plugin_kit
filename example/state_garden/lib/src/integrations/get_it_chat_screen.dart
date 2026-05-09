import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: GetIt as a session locator.
///
/// The host registers the active [PluginSession] into a [GetIt] instance at
/// app boot. The screen looks it up by type. GetIt does not own the session
/// lifecycle: the dispose discipline (cancel subscription on State.dispose,
/// dispose the runtime at app shutdown) is identical to the setState
/// recipe.
///
/// This recipe is intentionally minimal. The only meaningful differentiator
/// from [SetStateChatScreen] is the `widget.locator.get<PluginSession>()`
/// lookup at the top of [State.initState]; every line below that is
/// identical to the setState pattern. Keep this recipe in mind as
/// "service-locator-style session resolution"; reach for the dialog-driven
/// scope ergonomics in `package:flutter_plugin_kit` if you want
/// `BuildContext`-based session access without the locator dependency.
class GetItChatScreen extends StatefulWidget {
  const GetItChatScreen({super.key, required this.locator});

  final GetIt locator;

  @override
  State<GetItChatScreen> createState() => _GetItChatScreenState();
}

class _GetItChatScreenState extends State<GetItChatScreen> {
  late final PluginSession _session = widget.locator.get<PluginSession>();
  StreamSubscription<void>? _subscription;
  List<ChatMessage> _messages = const <ChatMessage>[];

  @override
  void initState() {
    super.initState();
    _subscription = _session.on<ChatMessagesChanged>(_onMessagesChanged);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onMessagesChanged(EventEnvelope<ChatMessagesChanged> envelope) {
    if (!mounted) return;
    setState(() => _messages = envelope.event.messages);
  }

  Future<void> _onSubmit(String text) =>
      _session.emit(SendMessageRequested(text)).then((_) {});

  @override
  Widget build(BuildContext context) {
    return ChatView(title: 'GetIt', messages: _messages, onSend: _onSubmit);
  }
}
