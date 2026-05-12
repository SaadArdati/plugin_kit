import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:provider/provider.dart';

import '../chat/chat_events.dart';
import '../chat/chat_message.dart';
import '../widgets/chat_view.dart';

/// Recipe: `PluginEventNotifier` from `flutter_plugin_kit`.
///
/// Drops in where the bespoke [ChangeNotifier] subclass would otherwise live.
/// The notifier subscribes to `session.on<ChatMessagesChanged>` in its
/// constructor, exposes the most recent event payload as [ChangeNotifier]
/// state via [PluginEventNotifier.value], and cancels the subscription in
/// [PluginEventNotifier.dispose]. There is no `_disposed` flag, no
/// [notifyListeners] call, and no [EventSubscription] field to maintain.
///
/// The widget passes the notifier through `ChangeNotifierProvider.value`
/// because the notifier is constructed once per screen and the provider
/// only owns its identity, not its lifetime.
class FlutterPluginKitNotifierChatScreen extends StatefulWidget {
  const FlutterPluginKitNotifierChatScreen({super.key, required this.session});

  final PluginSession session;

  @override
  State<FlutterPluginKitNotifierChatScreen> createState() =>
      _FlutterPluginKitNotifierChatScreenState();
}

class _FlutterPluginKitNotifierChatScreenState
    extends State<FlutterPluginKitNotifierChatScreen> {
  late final PluginEventNotifier<ChatMessagesChanged> _notifier =
      PluginEventNotifier<ChatMessagesChanged>(widget.session);

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  Future<void> _onSubmit(String text) =>
      widget.session.emit(SendMessageRequested(text)).then((_) {});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<
      PluginEventNotifier<ChatMessagesChanged>
    >.value(
      value: _notifier,
      child: _FlutterPluginKitNotifierBody(onSubmit: _onSubmit),
    );
  }
}

class _FlutterPluginKitNotifierBody extends StatelessWidget {
  const _FlutterPluginKitNotifierBody({required this.onSubmit});

  final Future<void> Function(String text) onSubmit;

  @override
  Widget build(BuildContext context) {
    final List<ChatMessage> messages =
        context
            .watch<PluginEventNotifier<ChatMessagesChanged>>()
            .value
            ?.messages ??
        const <ChatMessage>[];
    return ChatView(
      title: 'flutter_plugin_kit (PluginEventNotifier)',
      messages: messages,
      onSend: onSubmit,
    );
  }
}
