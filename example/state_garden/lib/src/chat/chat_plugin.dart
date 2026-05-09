import 'package:plugin_kit/plugin_kit.dart';

import 'chat_service.dart';

/// Session-scoped plugin that registers [ChatService] under [serviceId].
///
/// One plugin instance is shared across sessions. Each session re-runs
/// [register] and constructs a fresh [ChatService] inline, so no state is
/// shared.
class ChatPlugin extends SessionPlugin {
  static const PluginId id = PluginId('chat');
  static const ServiceId serviceId = ServiceId('service');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ChatService>(serviceId, ChatService());
  }
}

/// Higher-priority registrant for the same [ChatPlugin.serviceId] slot.
///
/// Used only by the hot-swap proof. Toggling this plugin's enabled flag
/// flips which concrete service [PluginSession.resolve] returns without
/// disposing the session.
class AltChatPlugin extends SessionPlugin {
  static const PluginId id = PluginId('alt_chat');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ChatService>(
      ChatPlugin.serviceId,
      AltChatService(),
      priority: 100,
    );
  }
}
