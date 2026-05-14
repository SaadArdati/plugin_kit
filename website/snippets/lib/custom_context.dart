/// Snippets for GlobalPluginContext and SessionPluginContext subclassing.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// Stub document type used in editor examples.
class Document {
  /// The document title.
  final String title;

  /// Creates a [Document] with [title].
  const Document({required this.title});
}

/// Stub user session type used in editor examples.
class UserSession {
  /// The user identifier.
  final String id;

  /// Creates a [UserSession] with [id].
  const UserSession({required this.id});
}

/// Stub editor application type.
class EditorApplication {
  /// The telemetry object for the application.
  final EditorTelemetry telemetry = EditorTelemetry();
}

/// Telemetry stub for editor analytics.
class EditorTelemetry {
  /// Starts the telemetry session.
  void start() {}
}

/// Stub feature flag client.
class FeatureFlagClient {
  /// Returns whether [flag] is enabled.
  bool isOn(String flag) => false;
}

/// An edit event indicating the document was modified.
class DocumentEdited {
  /// Creates a [DocumentEdited] event.
  const DocumentEdited();
}

/// A function that schedules a save for [document] with [userId].
void scheduleSave(Document document, String userId) {}

// #docregion session-plugin-context-subclass
class EditorSessionContext extends SessionPluginContext {
  /// The document open in this session.
  final Document document;

  /// The user who owns this session.
  final UserSession user;

  /// Creates an [EditorSessionContext].
  EditorSessionContext({
    required super.registry,
    required super.bus,
    required super.globalBus,
    super.extras,
    required this.document,
    required this.user,
  });

  @override
  EditorSessionContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
    EventBus? globalBus,
  }) {
    return EditorSessionContext(
      registry: registry ?? this.registry.copy(),
      bus: bus ?? this.bus,
      globalBus: globalBus ?? this.globalBus,
      extras: extras ?? this.extras,
      document: document,
      user: user,
    );
  }
}
// #enddocregion session-plugin-context-subclass

// #docregion session-plugin-typed-context
class AutosavePlugin extends SessionPlugin<EditorSessionContext> {
  @override
  PluginId get pluginId => const PluginId('autosave');

  @override
  void attach(EditorSessionContext context) {
    on<DocumentEdited>(context, (_) {
      scheduleSave(context.document, context.user.id);
    });
  }
}
// #enddocregion session-plugin-typed-context

// #docregion global-plugin-context-subclass
class EditorGlobalContext extends GlobalPluginContext {
  /// The running editor application.
  final EditorApplication application;

  /// The feature flag client for runtime toggles.
  final FeatureFlagClient flags;

  /// Creates an [EditorGlobalContext].
  EditorGlobalContext({
    required super.registry,
    required super.bus,
    required super.sessions,
    super.extras,
    required this.application,
    required this.flags,
  });

  @override
  EditorGlobalContext copyWith({
    ServiceRegistry? registry,
    Map<String, Object>? extras,
    EventBus? bus,
    List<PluginSession<SessionPluginContext>>? sessions,
  }) {
    return EditorGlobalContext(
      registry: registry ?? this.registry.copy(),
      bus: bus ?? this.bus,
      sessions: sessions ?? this.sessions,
      extras: extras ?? this.extras,
      application: application,
      flags: flags,
    );
  }
}
// #enddocregion global-plugin-context-subclass

// #docregion global-plugin-typed-context
class AnalyticsPlugin extends GlobalPlugin<EditorGlobalContext> {
  @override
  PluginId get pluginId => const PluginId('analytics');

  @override
  void attach(EditorGlobalContext context) {
    if (context.flags.isOn('analytics_v2')) {
      context.application.telemetry.start();
    }
  }
}
// #enddocregion global-plugin-typed-context

// #docregion plugin-context-stub
PluginContext makeTestContext() {
  // `.stub()` defaults to `ServiceRegistry.empty()` and a fresh `EventBus()`.
  // Pass overrides only when you need to swap in a fake.
  return PluginContext.stub();
}
// #enddocregion plugin-context-stub

// #docregion session-plugin-context-stub
SessionPluginContext makeTestSessionContext() {
  return SessionPluginContext.stub();
}
// #enddocregion session-plugin-context-stub

// #docregion global-plugin-context-stub
GlobalPluginContext makeTestGlobalContext() {
  return GlobalPluginContext.stub();
}
// #enddocregion global-plugin-context-stub

// #docregion custom-context-runtime-init
/// Demonstrates passing custom context factories to runtime.init and
/// createSession.
Future<void> initWithCustomContextFactories() async {
  final runtime = PluginRuntime<EditorGlobalContext, EditorSessionContext>(
    plugins: [AnalyticsPlugin()],
  );
  runtime.init(
    globalContextFactory: (registry, bus, sessions) => EditorGlobalContext(
      registry: registry,
      bus: bus,
      sessions: sessions,
      application: EditorApplication(),
      flags: FeatureFlagClient(),
    ),
  );

  final session = await runtime.createSession(
    contextFactory: (registry, sessionBus, globalBus) => EditorSessionContext(
      registry: registry,
      bus: sessionBus,
      globalBus: globalBus,
      document: const Document(title: 'untitled'),
      user: const UserSession(id: 'user-1'),
    ),
  );

  print('session ready: ${session.context.document.title}');
  await runtime.dispose();
}

// #enddocregion custom-context-runtime-init
