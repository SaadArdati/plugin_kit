/// Snippets for createSession, updateSessionSettings, multi-session isolation,
/// and cross-scope broadcasting.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// Current theme model used in theme broadcast examples.
class Theme {
  /// Theme name identifier.
  final String name;

  /// Creates a [Theme] with [name].
  const Theme({required this.name});
}

/// Event emitted when the application theme changes.
class AppThemeChanged {
  /// The new theme.
  final Theme theme;

  /// Creates an [AppThemeChanged] event.
  const AppThemeChanged(this.theme);
}

// #docregion theme-service-broadcast
class ThemeService extends StatefulPluginService<GlobalPluginContext> {
  /// Broadcasts [theme] to every active session.
  Future<void> broadcast(Theme theme) async {
    await context.sessions.emit<AppThemeChanged>(AppThemeChanged(theme));
  }
}

class ThemePlugin extends GlobalPlugin<GlobalPluginContext> {
  @override
  PluginId get pluginId => const PluginId('theme');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ThemeService>(
      const ServiceId('theme_service'),
      () => ThemeService(),
    );
  }
}

// In your app shell, resolve and call:
Future<void> applyTheme(PluginRuntime runtime, Theme currentTheme) async {
  final themeService = runtime.globalRegistry.resolve<ThemeService>(
    const ServiceId('theme_service'),
  );
  await themeService.broadcast(currentTheme);
}

class ThemeAwarePlugin extends SessionPlugin<SessionPluginContext> {
  @override
  PluginId get pluginId => const PluginId('theme_aware');

  @override
  void attach(SessionPluginContext context) {
    on<AppThemeChanged>(context, (e) {
      // fires because ThemeService.broadcast used sessions.emit
      print('Theme changed to: ${e.event.theme.name}');
    });
  }
}
// #enddocregion theme-service-broadcast

// #docregion create-session-with-factory
Future<void> createSessionWithFactory(PluginRuntime runtime) async {
  final session = await runtime.createSession(
    contextFactory: (registry, sessionBus, globalBus) => SessionPluginContext(
      registry: registry,
      bus: sessionBus,
      globalBus: globalBus,
      extras: const {'session_id': 'chat-42'},
    ),
  );

  print('session id: ${session.context.extras['session_id']}');
}
// #enddocregion create-session-with-factory

// #docregion session-update-settings
Future<void> updateSessionPlugin(
  PluginRuntime runtime,
  PluginSession session,
) async {
  final next = RuntimeSettings(
    plugins: {
      ...session.settings.plugins,
      const PluginId('experimental_feature'): const PluginConfig(enabled: true),
    },
  );
  await runtime.updateSessionSettings(session, newSettings: next);
}
// #enddocregion session-update-settings

// #docregion multi-session-isolation
Future<void> demonstrateMultiSessionIsolation(PluginRuntime runtime) async {
  final sessionA = await runtime.createSession();
  final sessionB = await runtime.createSession();

  // Each session has its own bus; events do not cross.
  sessionA.bus.on<AppThemeChanged>((e) => print('A: ${e.event.theme.name}'));

  await sessionA.bus.emit<AppThemeChanged>(
    event: const AppThemeChanged(Theme(name: 'dark')),
  );
  // Session B's subscriber never fires.

  await sessionA.dispose();
  await sessionB.dispose();
}
// #enddocregion multi-session-isolation

// #docregion sessions-emit-global-bus
/// Session plugin emits on globalBus to reach global-scope handlers.
class DocumentSaved {
  /// The document identifier that was saved.
  final String documentId;

  /// Creates a [DocumentSaved] event.
  const DocumentSaved({required this.documentId});
}

/// Demonstrates emitting on globalBus from a session plugin context.
Future<void> emitOnGlobalBus(SessionPluginContext context) async {
  await context.globalBus.emit<DocumentSaved>(
    event: const DocumentSaved(documentId: 'doc-42'),
  );
}
// #enddocregion sessions-emit-global-bus

// #docregion sessions-emit-global-plugin
/// A simple system-ready marker event.
class SystemReady {
  /// Creates a [SystemReady] event.
  const SystemReady();
}

/// Global plugin emits on context.bus (the global bus).
Future<void> emitOnGlobalPluginBus(GlobalPluginContext context) async {
  await context.bus.emit<SystemReady>(event: const SystemReady());
}
// #enddocregion sessions-emit-global-plugin

// #docregion sessions-emit-session-plugin
/// A user message passed through the session bus.
class SessionUserMessage {
  /// The message text.
  final String text;

  /// Creates a [SessionUserMessage] with [text].
  const SessionUserMessage(this.text);
}

/// Session plugin emits on context.bus (the session bus).
Future<void> emitOnSessionBus(SessionPluginContext context, String text) async {
  await context.bus.emit<SessionUserMessage>(event: SessionUserMessage(text));
}

// #enddocregion sessions-emit-session-plugin
