import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: `PluginSessionStateListener` from `flutter_plugin_kit`.
///
/// Same shape as the `setState` recipe, but the mixin owns subscription
/// bookkeeping: there is no [EventSubscription] field, no manual
/// [State.dispose] cancel, and no `_wired` deferral. [listen] is callable
/// from [State.initState]; the binding is attached against the active
/// session as soon as one is available, cancelled on dispose, and
/// re-attached automatically across session swaps.
///
/// The mixin also enforces a `mounted` check before invoking the user
/// handler, so the inner [setState] does not need its own guard.
///
/// `session` is overridden to read from [widget.session] because this
/// screen is invoked directly with an explicit session. When the session
/// lives in an ambient `PluginSessionScope`, drop the override and the
/// mixin will read the scope by default.
class FlutterPluginKitChatScreen extends StatefulWidget {
  const FlutterPluginKitChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  State<FlutterPluginKitChatScreen> createState() =>
      _FlutterPluginKitChatScreenState();
}

class _FlutterPluginKitChatScreenState extends State<FlutterPluginKitChatScreen>
    with PluginSessionStateListener<FlutterPluginKitChatScreen> {
  @override
  PluginSession? get session => widget.session;

  List<ChatMessage> _messages = const <ChatMessage>[];

  @override
  void initState() {
    super.initState();
    listen<ChatMessagesChanged>((envelope) {
      setState(() => _messages = envelope.event.messages);
    });
  }

  Future<void> _onSubmit(String text) =>
      widget.session.emit(SendMessageRequested(text)).then((_) {});

  @override
  Widget build(BuildContext context) {
    return ChatView(
      title: 'flutter_plugin_kit',
      messages: _messages,
      onSend: _onSubmit,
    );
  }
}
