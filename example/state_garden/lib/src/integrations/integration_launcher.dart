import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'bloc_chat.dart';
import 'change_notifier_chat.dart';
import 'flutter_plugin_kit_chat_screen.dart';
import 'flutter_plugin_kit_notifier_chat.dart';
import 'get_it_chat_screen.dart';
import 'mobx_chat.dart';
import 'plugin_kit_session_listener_chat.dart';
import 'riverpod_chat.dart';
import 'set_state_chat_screen.dart';
import 'signals_chat.dart';

/// Menu screen listing every integration recipe.
///
/// Tapping an entry pushes the corresponding screen with the supplied
/// [session]. The Riverpod entry assumes a `ProviderScope` higher up has
/// overridden `sessionProvider` with the same session.
///
/// Each tile dispatches via an inline `MaterialPageRoute` builder (the
/// framework requires a `builder` callback for lazy route construction);
/// no widget-returning helper functions are introduced.
class IntegrationLauncher extends StatelessWidget {
  const IntegrationLauncher({
    super.key,
    required this.session,
    required this.locator,
  });

  final PluginSession session;
  final GetIt locator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('plugin_kit state proofs')),
      body: ListView(
        children: <Widget>[
          IntegrationLauncherEntry(
            label: 'setState',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SetStateChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'flutter_plugin_kit (State mixin)',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => FlutterPluginKitChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'ChangeNotifier + provider',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => ChangeNotifierChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'plugin_kit (PluginSessionListener mixin)',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    PluginSessionListenerChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'flutter_plugin_kit (PluginEventNotifier)',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) =>
                    FlutterPluginKitNotifierChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'flutter_bloc Cubit',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => BlocChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'Riverpod AsyncNotifier',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const RiverpodChatScreen(),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'signals_flutter',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => SignalsChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'MobX',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => MobxChatScreen(session: session),
              ),
            ),
          ),
          IntegrationLauncherEntry(
            label: 'GetIt',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => GetItChatScreen(locator: locator),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row in [IntegrationLauncher]. Public so consumers (example apps, custom
/// hosts) can compose their own lists.
class IntegrationLauncherEntry extends StatelessWidget {
  const IntegrationLauncherEntry({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(label), onTap: onTap);
  }
}
