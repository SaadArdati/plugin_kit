/// Snippets for PluginRuntimeScope, PluginSessionScope,
/// PluginSessionStateListener, PluginEventNotifier, BuildContext extensions.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// A message event emitted by the chat system.
class ChatMessageReceived {
  /// The message text.
  final String text;

  /// Creates a [ChatMessageReceived] event.
  const ChatMessageReceived({required this.text});
}

/// A panel widget factory abstraction.
abstract class PanelWidgetFactory {
  /// Builds the panel widget.
  Widget build(BuildContext context);
}

/// A UI refresh request event.
class UIRefreshRequest {
  /// Creates a [UIRefreshRequest].
  const UIRefreshRequest();
}

/// A stub plugin for chat functionality.
class ChatPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('chat');
}

/// A stub plugin for assistant functionality.
class AssistantPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('assistant');
}

// #docregion flutter-runtime-scope-in-app
void exampleAppRoot() {
  runApp(
    MaterialApp(
      home: PluginRuntimeScope(
        plugins: [ChatPlugin(), AssistantPlugin()],
        child: const PluginSessionScope(
          child: ChatScreen(),
        ),
      ),
    ),
  );
}

class ChatScreen extends StatefulWidget {
  /// Creates a [ChatScreen].
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with PluginSessionStateListener<ChatScreen> {
  String? _last;

  @override
  void initState() {
    super.initState();
    listen<ChatMessageReceived>((event) {
      setState(() => _last = event.text);
    });
  }

  @override
  Widget build(BuildContext context) => Text(_last ?? 'idle');
}
// #enddocregion flutter-runtime-scope-in-app

// #docregion flutter-builder-watch-event
Widget buildWatchEventExample() {
  return Builder(
    builder: (context) {
      final last = context.watchEvent<ChatMessageReceived>();
      return Text(last?.text ?? 'idle');
    },
  );
}
// #enddocregion flutter-builder-watch-event

/// A terminal command history service that emits refresh events.
class TerminalPanelFactory extends StatefulPluginService
    implements PanelWidgetFactory {
  final List<String> _history = [];

  @override
  Widget build(BuildContext context) {
    return Text(_history.join('\n'));
  }

  /// Runs [command] and emits a [UIRefreshRequest].
  Future<void> run(String command) async {
    _history.add(command);
    await emit(const UIRefreshRequest());
  }
}

// #docregion flutter-terminal-plugin
class TerminalPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('terminal');

  @override
  void register(ScopedServiceRegistry registry) {
    const panel = Namespace('panel');
    registry.registerSingleton<PanelWidgetFactory>(
      panel('terminal'), // ServiceId('panel.terminal')
      () => TerminalPanelFactory(),
    );
  }
}
// #enddocregion flutter-terminal-plugin

// #docregion flutter-toggle-pending-serialize
class TogglePendingExample {
  /// Pending toggle future, tail-chained to serialize back-to-back toggles.
  Future<void> togglePending = Future.value();

  /// Serializes plugin enable/disable toggles to avoid race conditions.
  Future<void> setEnabled(PluginId pluginId, bool enabled) async {
    togglePending = togglePending.then((_) async {
      // compute next settings from the session's current state,
      // then updateSessionSettings, then refresh UI
    });
    await togglePending;
  }
}
// #enddocregion flutter-toggle-pending-serialize

/// A search service abstraction.
abstract class SearchService {
  /// Performs [query] and returns results.
  List<String> search(String query);
}

/// Fake implementation for tests.
class FakeSearch implements SearchService {
  @override
  List<String> search(String query) => ['fake_$query'];
}

// #docregion flutter-fake-search-plugin
class FakeSearchPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('fake_search');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<SearchService>(
      const ServiceId('search'),
      () => FakeSearch(),
      priority: Priority.system, // beat any other registrant
    );
  }
}
// #enddocregion flutter-fake-search-plugin

// #docregion flutter-chat-controller
/// Pure-Dart controller that uses [PluginSessionListener] to subscribe to
/// [ChatMessageReceived] events without depending on Flutter.
class ChatController with PluginSessionListener {
  /// Creates a [ChatController] bound to [session] and attaches subscriptions.
  ChatController(this.session) {
    attachSubscriptions();
  }

  @override
  final PluginSession session;

  @override
  List<EventBinding> get subscriptions => [
        EventBinding.on<ChatMessageReceived>(_onReceived),
      ];

  void _onReceived(ChatMessageReceived event) {
    // React to the incoming chat message.
    print('received: ${event.text}');
  }

  /// Cancels all active subscriptions.
  void dispose() => detachSubscriptions();
}
// #enddocregion flutter-chat-controller

// #docregion flutter-plugin-event-notifier
/// Example Bloc-style cubit that bridges session events.
class PluginEventCubit<E> {
  /// The current event value.
  E? value;

  late final StreamSubscription<void> _sub;

  /// Creates a cubit listening to [session] for events of type [E].
  PluginEventCubit(PluginSession session) {
    _sub = session.on<E>((envelope) {
      value = envelope.event;
    });
  }

  /// Cancels the subscription.
  void close() {
    _sub.cancel();
  }
}
// #enddocregion flutter-plugin-event-notifier

/// A panel descriptor issued by plugins to declare a named panel.
class PanelDescriptor {
  /// The panel identifier.
  final String id;

  /// Creates a [PanelDescriptor] with [id].
  const PanelDescriptor(this.id);
}

/// Mutable collection event; plugins append panel descriptors to [panels].
class CollectPanels {
  /// The accumulating list of panels contributed by plugins.
  final List<PanelDescriptor> panels = [];
}

/// A minimap plugin stub.
class MinimapPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('minimap');
}

// #docregion flutter-editor-shell-state
class EditorScreen extends StatefulWidget {
  /// Creates an [EditorScreen].
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final PluginRuntime _runtime;
  PluginSession? _session;

  List<PanelDescriptor> _panels = [];

  @override
  void initState() {
    super.initState();
    _runtime = PluginRuntime(
      plugins: [TerminalPlugin(), MinimapPlugin()],
    );
    _runtime.init();
    _createSession();
  }

  Future<void> _createSession() async {
    _session = await _runtime.createSession();

    _session!.on<UIRefreshRequest>((_) async {
      if (!mounted) return;
      await _collectPanels();
    });

    await _collectPanels();
  }

  Future<void> _collectPanels() async {
    final collect = CollectPanels();
    await _session!.emit(collect);

    if (!mounted) return;
    setState(() => _panels = collect.panels);
  }

  @override
  void dispose() {
    // runtime.dispose() iterates and disposes active sessions. Do NOT call
    // session.dispose() separately. Doing both races on stateful service
    // detach and can throw ConcurrentModificationError.
    _runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          for (final panel in _panels) _resolvePanel(panel),
        ],
      ),
    );
  }

  Widget _resolvePanel(PanelDescriptor panel) {
    const ns = Namespace('panel');
    final factory = _session?.context.maybeResolve<PanelWidgetFactory>(
      ns(panel.id),
    );
    return factory?.build(context) ?? const SizedBox.shrink();
  }
}
// #enddocregion flutter-editor-shell-state

// #docregion flutter-plugin-kit-runtime-scope
/// Demonstrates the auto-create form of PluginRuntimeScope.
Widget buildRuntimeScopeAutoCreate() {
  return PluginRuntimeScope(
    plugins: [ChatPlugin(), AssistantPlugin()],
    initialSettings: const RuntimeSettings.empty(),
    child: const ChatScreen(),
  );
}
// #enddocregion flutter-plugin-kit-runtime-scope

// #docregion flutter-plugin-kit-runtime-scope-value
/// Demonstrates the external-ownership form of PluginRuntimeScope.
Widget buildRuntimeScopeExternalOwnership(PluginRuntime runtime) {
  return PluginRuntimeScope.value(
    runtime: runtime,
    child: const ChatScreen(),
  );
}
// #enddocregion flutter-plugin-kit-runtime-scope-value

// #docregion flutter-plugin-kit-session-scope-ambient
/// Demonstrates PluginSessionScope reading from an ambient PluginRuntimeScope.
Widget buildSessionScopeAmbient() {
  return PluginRuntimeScope(
    plugins: [ChatPlugin(), AssistantPlugin()],
    child: const PluginSessionScope(
      loading: _circularProgress,
      child: ChatScreen(),
    ),
  );
}

Widget _circularProgress(BuildContext context) =>
    const Center(child: CircularProgressIndicator());
// #enddocregion flutter-plugin-kit-session-scope-ambient

// #docregion flutter-plugin-kit-session-scope-runtime
/// Demonstrates PluginSessionScope with an explicit runtime.
Widget buildSessionScopeExplicitRuntime(PluginRuntime someRuntime) {
  return PluginSessionScope(
    runtime: someRuntime,
    child: const ChatScreen(),
  );
}
// #enddocregion flutter-plugin-kit-session-scope-runtime

// #docregion flutter-plugin-kit-session-scope-external
/// Demonstrates PluginSessionScope with an externally-owned session.
Widget buildSessionScopeExternalSession(PluginSession existingSession) {
  return PluginSessionScope(
    session: existingSession,
    child: const ChatScreen(),
  );
}
// #enddocregion flutter-plugin-kit-session-scope-external

// #docregion flutter-plugin-kit-state-listener-full
class FullChatScreen extends StatefulWidget {
  /// Creates a [FullChatScreen].
  const FullChatScreen({super.key});

  @override
  State<FullChatScreen> createState() => _FullChatScreenState();
}

class _FullChatScreenState extends State<FullChatScreen>
    with PluginSessionStateListener<FullChatScreen> {
  String? _last;

  @override
  void initState() {
    super.initState();
    listen<ChatMessageReceived>((event) {
      if (!mounted) return;
      setState(() => _last = event.text);
    });
  }

  @override
  Widget build(BuildContext context) => Text(_last ?? 'idle');
}
// #enddocregion flutter-plugin-kit-state-listener-full

// #docregion flutter-plugin-kit-state-listener-session-override
/// Pane that explicitly overrides [session] from a widget parameter.
class Pane extends StatefulWidget {
  /// The session to listen to.
  final PluginSession session;

  /// Creates a [Pane] bound to [session].
  const Pane({super.key, required this.session});

  @override
  State<Pane> createState() => _PaneState();
}

class _PaneState extends State<Pane> with PluginSessionStateListener<Pane> {
  @override
  PluginSession? get session => widget.session;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
// #enddocregion flutter-plugin-kit-state-listener-session-override

// #docregion flutter-plugin-kit-watch-read-event
/// Demonstrates watchEvent and readEvent extensions.
Widget buildWatchReadEventExample() {
  return Builder(
    builder: (context) {
      final last = context.watchEvent<ChatMessageReceived>();
      final maybe = context.readEvent<ChatMessageReceived>();
      return Text('watch=${last?.text} read=${maybe?.text}');
    },
  );
}
// #enddocregion flutter-plugin-kit-watch-read-event

// #docregion flutter-plugin-kit-provider-notifier
/// Demonstrates PluginEventNotifier in a provider-style widget.
Widget buildProviderNotifierExample(PluginSession session) {
  return PluginEventNotifierConsumer<ChatMessageReceived>(session: session);
}

/// A widget that reads from a [PluginEventNotifier] of [ChatMessageReceived].
class PluginEventNotifierConsumer<E> extends StatefulWidget {
  /// The session to bind the notifier to.
  final PluginSession session;

  /// Creates a [PluginEventNotifierConsumer].
  const PluginEventNotifierConsumer({super.key, required this.session});

  @override
  State<PluginEventNotifierConsumer<E>> createState() =>
      _PluginEventNotifierConsumerState<E>();
}

class _PluginEventNotifierConsumerState<E>
    extends State<PluginEventNotifierConsumer<E>> {
  late final PluginEventNotifier<E> _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = PluginEventNotifier<E>(widget.session);
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) => Text('event: ${_notifier.value}'),
    );
  }
}
// #enddocregion flutter-plugin-kit-provider-notifier

// #docregion flutter-plugin-kit-bloc-cubit
/// A simple Bloc-style cubit that bridges a session event of type [E].
class PluginEventCubitTyped<E> {
  /// The latest event value.
  E? value;

  late final StreamSubscription<void> _sub;

  /// Creates a cubit subscribed to [session] for events of type [E].
  PluginEventCubitTyped(PluginSession session) : super() {
    _sub = session.on<E>((envelope) {
      value = envelope.event;
    });
  }

  /// Cancels the subscription, mirroring Cubit.close.
  Future<void> close() async {
    _sub.cancel();
  }
}
// #enddocregion flutter-plugin-kit-bloc-cubit

// #docregion flutter-migrating-editor-screen
/// A Flutter screen that owns a [PluginRuntime] and a [PluginSession].
class EditorScreenMigration extends StatefulWidget {
  /// Creates an [EditorScreenMigration].
  const EditorScreenMigration({super.key});

  @override
  State<EditorScreenMigration> createState() => _EditorScreenMigrationState();
}

class _EditorScreenMigrationState extends State<EditorScreenMigration> {
  late final PluginRuntime _plugins;

  PluginSession? _session;

  @override
  void initState() {
    super.initState();
    _plugins = PluginRuntime(
      plugins: [
        ChatPlugin(),
        AssistantPlugin(),
      ],
    );
    _plugins.init();
    _createSession();
  }

  Future<void> _createSession() async {
    final session = await _plugins.createSession();
    if (!mounted) return;
    setState(() => _session = session);
  }

  @override
  void dispose() {
    _plugins.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Text('session active: ${session.context.extras}');
  }
}
// #enddocregion flutter-migrating-editor-screen

// #docregion flutter-integration-test-widgets
/// Demonstrates the pattern for testing a Flutter widget backed by a runtime.
Future<void> pumpEditorShell(
  PluginRuntime runtime,
  Future<void> Function(Widget) pump,
) async {
  runtime.init();
  await pump(const MaterialApp(home: EditorScreen()));
}
// #enddocregion flutter-integration-test-widgets

// #docregion flutter-plugin-kit-runtime-scope-value-block
/// Demonstrates the .value (external-ownership) form of PluginRuntimeScope.
///
/// The caller owns the runtime's lifetime; the scope holds a reference
/// but does not dispose on unmount.
Widget buildRuntimeScopeValueBlock(PluginRuntime runtime) {
  return PluginRuntimeScope.value(
    runtime: runtime,
    child: const ChatScreen(),
  );
}
// #enddocregion flutter-plugin-kit-runtime-scope-value-block

/// A stub chat-body widget for provider/notifier examples.
class ChatBody extends StatelessWidget {
  /// Creates a [ChatBody].
  const ChatBody({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// #docregion flutter-plugin-kit-event-notifier-provider
/// Demonstrates using [PluginEventNotifier] with a ChangeNotifierProvider.
///
/// The notifier subscribes to the session from [PluginSessionScope] and
/// exposes the latest [ChatMessageReceived] as `.value`.
Widget buildEventNotifierProvider(PluginSession session) {
  return ListenableBuilder(
    listenable: PluginEventNotifier<ChatMessageReceived>(session),
    builder: (context, _) => const ChatBody(),
  );
}
// #enddocregion flutter-plugin-kit-event-notifier-provider

// #docregion flutter-plugin-kit-event-cubit
/// A Cubit-style bridge that subscribes to [PluginSession] events of type [E].
class SessionEventCubit<E> {
  /// The latest received event, or null before the first event arrives.
  E? value;

  late final StreamSubscription<void> _sub;

  /// Creates a [SessionEventCubit] subscribed to [session].
  SessionEventCubit(PluginSession session) {
    _sub = session.on<E>((envelope) {
      value = envelope.event;
    });
  }

  /// Cancels the subscription, mirroring Cubit.close.
  Future<void> close() async {
    _sub.cancel();
  }
}
// #enddocregion flutter-plugin-kit-event-cubit
