/// Snippets for Plugin, GlobalPlugin, SessionPlugin, PluginRuntime,
/// PluginSession, attach, detach, dependencies, and FeatureFlag.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// A simple greeter abstraction used by the greeting plugins.
abstract class Greeter {
  /// Returns a greeting string for [name].
  String greet(String name);
}

/// Casual implementation of [Greeter].
class CasualGreeter implements Greeter {
  @override
  String greet(String name) => 'Hello, $name.';
}

/// Formal implementation of [Greeter].
class FormalGreeter implements Greeter {
  @override
  String greet(String name) => 'Good day, $name.';
}

// #docregion session-plugin-basic
class CasualPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('casual');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => CasualGreeter(),
    );
  }
}

class FormalPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('formal');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => FormalGreeter(),
      priority: Priority.elevated, // wins (beats Priority.normal default)
    );
  }
}

Future<void> runGreeterExample() async {
  final runtime = PluginRuntime(plugins: [CasualPlugin(), FormalPlugin()])
    ..init();
  final session = await runtime.createSession();

  final greeter = session.resolve<Greeter>(const ServiceId('greeter'));
  print(greeter.greet('world')); // Good day, world.

  await runtime.dispose();
}
// #enddocregion session-plugin-basic

// #docregion feature-flag
class ExperimentalPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('experimental_feature');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.experimental];

  @override
  void register(ScopedServiceRegistry registry) {}
}
// #enddocregion feature-flag

// #docregion locked-plugin
class CorePlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('core');

  @override
  List<FeatureFlag> get featureFlags => const [FeatureFlag.locked];

  @override
  void register(ScopedServiceRegistry registry) {}
}
// #enddocregion locked-plugin

// #docregion plugin-multiple-feature-flags
/// Plugin that declares multiple feature flags: experimental and a custom tag.
class NetworkPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('network_plugin');

  @override
  List<FeatureFlag> get featureFlags => const [
    FeatureFlag.experimental,
    FeatureFlag('requires_network'),
  ];

  @override
  void attach(GlobalPluginContext context) {}
}
// #enddocregion plugin-multiple-feature-flags

// #docregion plugin-dependencies
class AnalyticsPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('analytics');

  @override
  Set<PluginId> get dependencies => const {PluginId('core')};

  @override
  void register(ScopedServiceRegistry registry) {}
}
// #enddocregion plugin-dependencies

/// A message event used in the greeter example.
class UserJoinedEvent {
  /// The id of the user who joined.
  final String userId;

  /// Creates a [UserJoinedEvent] with the given [userId].
  const UserJoinedEvent(this.userId);
}

/// Greeter service registered by the plugin.
class GreeterService {
  /// Says hello to the user with [userId].
  void sayHello(String userId) {
    print('Hello, $userId!');
  }
}

// #docregion session-plugin-attach
class GreeterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('greeter');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<GreeterService>(
      const ServiceId('greeter_service'),
      () => GreeterService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    on<UserJoinedEvent>(context, (event) {
      final greeter = context.resolve<GreeterService>(
        const ServiceId('greeter_service'),
      );
      greeter.sayHello(event.event.userId);
    });
  }
}
// #enddocregion session-plugin-attach

// #docregion runtime-init-default-enabled
void initWithDefaults(PluginRuntime runtime, RuntimeSettings savedSettings) {
  runtime.init(
    settings: savedSettings,
    defaultEnabledPluginIds: const {
      PluginId('core'),
      PluginId('search'),
      PluginId('telemetry'),
    },
  );
}
// #enddocregion runtime-init-default-enabled

// #docregion runtime-update-settings
Future<void> disableAnalytics(PluginRuntime runtime) async {
  final next = runtime.settings.copyWith(
    plugins: {
      ...runtime.settings.plugins,
      const PluginId('analytics'): const PluginConfig(enabled: false),
    },
  );

  await runtime.updateSettings(next);
}
// #enddocregion runtime-update-settings

// #docregion runtime-update-snapshot
/// Shows the two settings-update modes: full reconciliation via
/// [PluginRuntime.updateSettings] and publish-only via
/// [PluginRuntime.updateSettingsSnapshot].
Future<void> demonstrateUpdateModes(PluginRuntime runtime) async {
  final newSettings = runtime.settings.copyWith(
    plugins: {
      ...runtime.settings.plugins,
      const PluginId('analytics'): const PluginConfig(enabled: false),
    },
  );

  await runtime.updateSettings(newSettings); // full reconcile

  final snapshot = runtime.settings.copyWith();
  runtime.updateSettingsSnapshot(snapshot); // publish without reconciling
}
// #enddocregion runtime-update-snapshot

/// Plugin that crashes on attach, used in lifecycle-exception examples.
class CrashingPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('crashing_plugin');

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('intentional crash');
  }
}

// #docregion introduction-casual-plugin
class CasualSessionPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('casual_session');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => CasualGreeter(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    on<UserJoinedEvent>(context, (e) {
      final greeter = context.resolve<Greeter>(const ServiceId('greeter'));
      print(greeter.greet(e.event.userId));
    });
  }
}

// #enddocregion introduction-casual-plugin

// #docregion introduction-plugin-taste
/// A casual greeter plugin registered at default priority.
class IntroductionCasualPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('casual');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => CasualGreeter(),
    );
  }
}

/// A formal greeter plugin registered at higher priority, which wins resolution.
class IntroductionFormalPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('formal');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => FormalGreeter(),
      priority: Priority.elevated, // wins (beats Priority.normal default)
    );
  }
}

// session.resolve<Greeter>(const ServiceId('greeter')).greet('world')
// → "Good day, world."
// #enddocregion introduction-plugin-taste

// #docregion getting-started-disable-plugin
/// Demonstrates disabling a plugin via RuntimeSettings.
Future<void> runWithDisabledPlugin() async {
  final runtime = PluginRuntime(plugins: [CasualPlugin(), FormalPlugin()])
    ..init(
      // Can be user-driven via JSON config, a settings UI, or any other config
      // system you build on top. Hard-coded here for demo purposes.
      settings: const RuntimeSettings(
        plugins: {PluginId('formal'): PluginConfig(enabled: false)},
      ),
    );
  final session = await runtime.createSession();
  final greeter = session.resolve<Greeter>(const ServiceId('greeter'));
  print(greeter.greet('world')); // Hello, world.
  await runtime.dispose();
}
// #enddocregion getting-started-disable-plugin

// #docregion settings-init-with-settings
/// Demonstrates initializing a runtime with explicit settings.
void initWithSettings(RuntimeSettings settings) {
  final runtime = PluginRuntime(plugins: [CasualPlugin(), FormalPlugin()])
    ..init(settings: settings);
  print('enabled: ${runtime.enabledPluginIds}');
}
// #enddocregion settings-init-with-settings

// #docregion settings-update-settings
/// Demonstrates calling updateSettings live.
Future<void> reconcileSettings(
  PluginRuntime runtime,
  RuntimeSettings nextSettings,
) async {
  await runtime.updateSettings(nextSettings);
}
// #enddocregion settings-update-settings

// #docregion settings-snapshot-only
/// Demonstrates the snapshot-only update path.
void snapshotOnly(PluginRuntime runtime, RuntimeSettings nextSettings) {
  runtime.updateSettingsSnapshot(nextSettings);
}
// #enddocregion settings-snapshot-only

// #docregion runtime-snapshot-then-reconcile
/// Demonstrates emitting optimistic snapshot then confirming with a full
/// reconciliation.
Future<void> snapshotThenReconcile(
  PluginRuntime runtime,
  RuntimeSettings pendingSettings,
) async {
  // Optimistic UI: settingsStream emits immediately.
  runtime.updateSettingsSnapshot(pendingSettings);

  // Later, if the user confirms, run the real reconciliation.
  await runtime.updateSettings(pendingSettings);
}
// #enddocregion runtime-snapshot-then-reconcile

// #docregion runtime-construct-and-session
/// Demonstrates the full construct → init → createSession lifecycle.
Future<void> constructAndSession() async {
  final runtime = PluginRuntime(plugins: [CasualPlugin(), FormalPlugin()]);

  runtime.init(settings: const RuntimeSettings.empty());

  final session = await runtime.createSession();
  print('session registry keys: ${session.registry.listAllServiceIds()}');
  await runtime.dispose();
}
// #enddocregion runtime-construct-and-session

// #docregion plugins-dependencies-override
class FormatterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('formatter');

  @override
  Set<PluginId> get dependencies => const {PluginId('formatter_pipeline')};

  @override
  void register(ScopedServiceRegistry registry) {}
}
// #enddocregion plugins-dependencies-override

// #docregion plugin-id-value-equality
/// Demonstrates PluginId string equality.
void demonstratePluginId() {
  const id = PluginId('greeter');

  print(id); // 'greeter'
  print(id == const PluginId('greeter')); // true (delegates to String equality)
}
// #enddocregion plugin-id-value-equality

/// An event that signals the cache should be invalidated.
class InvalidateCacheEvent {
  /// Creates an [InvalidateCacheEvent].
  const InvalidateCacheEvent();
}

// #docregion sessions-broadcast-invalidate-cache
/// Demonstrates broadcasting [InvalidateCacheEvent] to every active session.
Future<void> broadcastInvalidateCache(GlobalPluginContext context) async {
  await context.sessions.emit<InvalidateCacheEvent>(
    const InvalidateCacheEvent(),
  );
}

// #enddocregion sessions-broadcast-invalidate-cache
