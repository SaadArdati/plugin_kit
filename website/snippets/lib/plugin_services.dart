/// Snippets for PluginService, StatefulPluginService, injectSettings,
/// settings injection patterns.
library;

import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';

/// A user message event used in service examples.
class UserMessage {
  /// The message text.
  final String text;

  /// Creates a [UserMessage] with [text].
  const UserMessage(this.text);
}

/// A stored message event emitted after recording.
class MessageStored {
  /// The stored message text.
  final String text;

  /// Creates a [MessageStored] with [text].
  const MessageStored(this.text);
}

/// A debug event used in service examples.
class DebugEvent {
  /// The debug action identifier.
  final String action;

  /// Creates a [DebugEvent] with [action].
  const DebugEvent({required this.action});
}

/// Conversation memory service storing message history.
class ConversationMemory {
  final List<String> _log = [];

  /// Appends [text] to the conversation log.
  void append(String text) => _log.add(text);

  /// The recorded messages.
  List<String> get messages => List.unmodifiable(_log);
}

// #docregion plugin-service-basic
class ModelRouter extends PluginService {
  /// The default model name read from injected settings.
  String get defaultModel => config.getString('default_model') ?? 'gpt-4.1';

  /// The temperature value read from injected settings.
  double get temperature => config.getDouble('temperature') ?? 0.7;
}
// #enddocregion plugin-service-basic

// #docregion plugin-service-settings-inject
class AnthropicService extends PluginService {
  /// The API key read from injected settings.
  String get apiKey => config.getString('api_key') ?? '';

  /// The temperature value read from injected settings.
  double get temperature => config.getDouble('temperature') ?? 0.7;
}
// #enddocregion plugin-service-settings-inject

// #docregion stateful-plugin-service-basic
class DebugAdapter extends StatefulPluginService {
  @override
  void attach() {
    on<DebugEvent>((e) {
      print('debug action: ${e.event.action}');
    });
  }

  @override
  Future<void> detach() async {
    print('adapter shutting down');
  }
}
// #enddocregion stateful-plugin-service-basic

// #docregion stateful-plugin-service-inject-settings
class CachedFormatter extends StatefulPluginService {
  String? compiledTemplate;

  @override
  void onSettingsInjected() {
    compiledTemplate = null;
  }
}
// #enddocregion stateful-plugin-service-inject-settings

// #docregion stateful-plugin-service-resolve-emit
class ConversationState extends StatefulPluginService {
  @override
  void attach() {
    on<UserMessage>((e) async {
      final memory = resolve<ConversationMemory>(const ServiceId('memory'));
      memory.append(e.event.text);
      await emit(MessageStored(e.event.text));
    });
  }
}
// #enddocregion stateful-plugin-service-resolve-emit

// #docregion plugin-service-settings-runtime
final serviceSettingsExample = RuntimeSettings(
  services: {
    const PluginId('model_router').service(const ServiceId('decider')):
        const ServiceSettings(config: {'default_model': 'gpt-4.1-mini'}),
  },
);
// #enddocregion plugin-service-settings-runtime

/// A new message event used in ChatThread.
class NewMessage {
  /// The text content of the message.
  final String text;

  /// Creates a [NewMessage] with [text].
  const NewMessage(this.text);
}

/// A placeholder message type for ChatThread.
class Message {
  /// The message text.
  final String text;

  /// Creates a [Message] with [text].
  const Message(this.text);
}

/// A stub client returned when the assistant is ready.
class AssistantClient {
  /// Sends [prompt] to the assistant.
  Future<String> complete(String prompt) async => 'response to $prompt';
}

/// Simulates the async work of connecting to an external assistant.
Future<AssistantClient> connectAssistant() async => AssistantClient();

/// Event emitted once the assistant connection is ready.
class AssistantReady {
  /// The connected client instance.
  final AssistantClient assistant;

  /// Creates an [AssistantReady] event with [assistant].
  const AssistantReady(this.assistant);
}

// #docregion migration-assistant-ready
/// Service that connects to an assistant in the background and broadcasts
/// [AssistantReady] once the connection succeeds.
class AssistantRuntimeService extends StatefulPluginService {
  @override
  void attach() {
    Future(() async {
      final assistant = await connectAssistant();
      await emit(AssistantReady(assistant));
    });
  }
}
// #enddocregion migration-assistant-ready

/// Request type used to retrieve the assistant once it is ready.
class WaitForAssistant {
  /// Creates a [WaitForAssistant] request.
  const WaitForAssistant();
}

// #docregion migration-wait-for-assistant
/// Service that lazily connects to an assistant and satisfies
/// [WaitForAssistant] requests once the connection resolves.
class AssistantRequestService extends StatefulPluginService {
  AssistantClient? _assistant;
  Future<AssistantClient?>? _connecting;

  @override
  void attach() {
    onRequest<WaitForAssistant, AssistantClient?>((_) async {
      return _assistant ??= await (_connecting ??= connectAssistant());
    });
  }
}
// #enddocregion migration-wait-for-assistant

// #docregion session-stateful-plugin-service
class ChatThread extends StatefulPluginService<SessionPluginContext> {
  /// The accumulated messages for this session.
  final List<Message> messages = [];

  @override
  void attach() {
    on<NewMessage>((e) => messages.add(Message(e.event.text)));
  }

  @override
  Future<void> detach() async {
    messages.clear();
  }
}

// #enddocregion session-stateful-plugin-service

// #docregion adding-plugin-notification-service
/// A simple notification service that prints a message.
class NotificationService {
  /// Sends [message] to the configured output channel.
  Future<void> send(String message) async {
    print(message);
  }
}
// #enddocregion adding-plugin-notification-service

/// A plugin that registers [NotificationService] in the session registry.
class SimpleNotificationPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('notifier');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<NotificationService>(
      const ServiceId('notification_service'),
      () => NotificationService(),
    );
  }
}

// #docregion adding-plugin-run-notification
/// Demonstrates constructing a runtime, creating a session,
/// resolving [NotificationService], and sending a notification.
Future<void> runNotificationExample() async {
  final runtime = PluginRuntime(plugins: [SimpleNotificationPlugin()])..init();

  final session = await runtime.createSession();

  final notifications = session.resolve<NotificationService>(
    const ServiceId('notification_service'),
  );

  await notifications.send('Build completed.');

  await runtime.dispose();
}
// #enddocregion adding-plugin-run-notification

// #docregion adding-plugin-chat-backend-service
/// A chat backend service that reads its API key and model from settings.
class ChatBackendService extends PluginService {
  /// The API key read from injected settings.
  String? get apiKey => config.getString('api_key');

  /// The model identifier read from injected settings.
  String get model => config.getString('model') ?? 'claude-opus-4-7';

  /// Sends [prompt] to the configured upstream API.
  Future<ChatReply> reply(String prompt) async {
    final key = apiKey;
    if (key == null) {
      throw StateError('No API key configured.');
    }
    // Call the upstream API with key and model.
    return ChatReply.stub();
  }
}

/// A minimal stub reply type for the chat backend example.
class ChatReply {
  /// The reply text.
  final String text;

  /// Creates a [ChatReply] with [text].
  const ChatReply(this.text);

  /// Returns a stub reply for demo purposes.
  factory ChatReply.stub() => const ChatReply('stub reply');
}
// #enddocregion adding-plugin-chat-backend-service

/// A generic server-side event type for the stream-bridge example.
class ServerEvent {
  /// The event payload text.
  final String payload;

  /// Creates a [ServerEvent] with [payload].
  const ServerEvent(this.payload);
}

// #docregion migrating-server-stream-plugin
/// Emitted by a plugin that owns an open server event stream.
/// Other plugins listen for this to subscribe to the raw stream.
class ServerEventStreamReady {
  /// The stream of server events.
  final Stream<ServerEvent> events;

  /// Creates a [ServerEventStreamReady] with [events].
  const ServerEventStreamReady(this.events);
}

/// Typed domain event wrapping one server-side event.
class ServerMessageReceived {
  /// The original server event.
  final ServerEvent event;

  /// Creates a [ServerMessageReceived] wrapping [event].
  const ServerMessageReceived(this.event);
}

/// Plugin that bridges a raw [ServerEvent] stream into the session bus.
class ServerStreamPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('server_stream');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ServerStreamBridge>(
      const ServiceId('server_stream_bridge'),
      () => ServerStreamBridge(),
    );
  }
}

/// Service that listens for a [ServerEventStreamReady] event and translates
/// the raw stream into typed [ServerMessageReceived] domain events.
class ServerStreamBridge extends StatefulPluginService {
  StreamSubscription<ServerEvent>? _serverSub;

  @override
  void attach() {
    on<ServerEventStreamReady>((envelope) {
      _serverSub?.cancel();
      _serverSub = envelope.event.events.listen((serverEvent) {
        emit(ServerMessageReceived(serverEvent));
      });
    });
  }

  @override
  Future<void> detach() async {
    await _serverSub?.cancel();
  }
}
// #enddocregion migrating-server-stream-plugin

/// A Notification plugin with [NotificationService] registered.
class NotificationPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('notification_plugin');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<NotificationService>(
      const ServiceId('notification_service'),
      () => NotificationService(),
    );
  }
}
