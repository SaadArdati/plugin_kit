/// Snippets for ServiceRegistry, register*, resolve*, scopedFor,
/// priority resolution, and delegation.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// A stub query builder service.
class QueryBuilder {
  /// Creates a [QueryBuilder].
  QueryBuilder();
}

/// A stub database service.
class Database {
  /// Connects to the database and returns an instance.
  static Database connect() => Database();
}

/// A stub application configuration service.
class AppConfig {
  /// Loads and returns the application configuration.
  static AppConfig load() => AppConfig();
}

/// A stub code formatter service.
abstract class Formatter {
  /// Formats [input], the contents of a file at [path], and returns the result.
  String format(String path, String input);
}

/// Default formatter implementation. Returns the input unchanged.
class DefaultFormatter implements Formatter {
  @override
  String format(String path, String input) => input;
}

/// Higher-quality formatter implementation. Trims whitespace.
class PrettierFormatter implements Formatter {
  @override
  String format(String path, String input) => input.trim();
}

/// Panel factory abstraction.
abstract class PanelWidgetFactory {
  /// A descriptive name for this panel.
  String get name;
}

/// Console panel factory implementation.
class ConsolePanelFactory implements PanelWidgetFactory {
  @override
  String get name => 'console';
}

/// Abstract model router.
abstract class ModelRouter {
  /// Returns a model identifier for [prompt], or null to concede.
  String? routeFor(String prompt);
}

/// Enterprise router that delegates to the next registration for unknown prompts.
class EnterpriseRouter implements ModelRouter {
  /// The plugin id that owns this router (needed for resolveAfter).
  final PluginId ownerId;

  /// Thunk that returns the live registry; deferred until first use.
  final ServiceRegistry Function() registryThunk;

  /// Creates an [EnterpriseRouter].
  EnterpriseRouter({required this.ownerId, required this.registryThunk});

  @override
  String? routeFor(String prompt) {
    if (prompt.toLowerCase().contains('enterprise')) return 'gpt-4-enterprise';
    return registryThunk()
        .resolveAfter<ModelRouter>(
          pluginId: ownerId,
          serviceId: const ServiceId('model_router'),
        )
        .routeFor(prompt);
  }
}

// #docregion service-registry-register-all-three
void registerAllThree(ScopedServiceRegistry registry) {
  registry.registerFactory<QueryBuilder>(
    const ServiceId('query_builder'),
    QueryBuilder.new,
  );

  registry.registerLazySingleton<Database>(
    const ServiceId('main_db'),
    () => Database.connect(),
  );

  registry.registerSingleton<AppConfig>(
    const ServiceId('config'),
    () => AppConfig.load(),
  );
}
// #enddocregion service-registry-register-all-three

// #docregion service-registry-resolve
void resolveFromContext(PluginContext context) {
  final db = context.resolve<Database>(const ServiceId('main_db'));
  final maybeLogger = context.maybeResolve<AppConfig>(
    const ServiceId('config'),
  );
  print('$db $maybeLogger');
}
// #enddocregion service-registry-resolve

// #docregion service-registry-priority
void registerWithPriority(ServiceRegistry registry) {
  registry.registerSingleton<Formatter>(
    pluginId: const PluginId('core'),
    serviceId: const ServiceId('code_formatter'),
    create: () => DefaultFormatter(),
    priority: Priority.normal,
  );

  registry.registerSingleton<Formatter>(
    pluginId: const PluginId('my_better_formatter'),
    serviceId: const ServiceId('code_formatter'),
    create: () => PrettierFormatter(),
    priority: Priority.elevated,
  );
}
// #enddocregion service-registry-priority

// #docregion service-registry-namespace
void registerNamespacedService(ScopedServiceRegistry registry) {
  const panel = Namespace('panel');

  registry.registerSingleton<PanelWidgetFactory>(
    panel('console'), // ServiceId('panel.console')
    () => ConsolePanelFactory(),
  );
}

PanelWidgetFactory resolveNamespaced(PluginContext context) {
  const panel = Namespace('panel');
  return context.resolve<PanelWidgetFactory>(panel('console'));
}
// #enddocregion service-registry-namespace

// #docregion service-registry-settings-injection
class AnthropicService extends PluginService {
  /// The API key from injected settings.
  String get apiKey => config.getString('api_key') ?? '';

  /// The temperature from injected settings.
  double get temperature => config.getDouble('temperature') ?? 0.7;
}
// #enddocregion service-registry-settings-injection

// #docregion service-registry-resolve-after
class BetterDartFormatter extends StatefulPluginService implements Formatter {
  @override
  String format(String path, String input) {
    if (path.endsWith('.dart')) {
      // Our specialty. Format it ourselves.
      return input.trim();
    }
    // Not a Dart file. Hand off to whichever Formatter was the previous winner.
    return context.registry
        .resolveAfter<Formatter>(pluginId: pluginId, serviceId: serviceId)
        .format(path, input);
  }
}
// #enddocregion service-registry-resolve-after

/// A formatter that consults the next-priority registrant defensively. The
/// `_maybeNext` helper wraps [ServiceRegistry.resolveAfter] in a try/catch so
/// the chain returns `null` rather than throwing when no fallback exists.
class OptionalFallbackFormatter extends StatefulPluginService
    implements Formatter {
  @override
  String format(String path, String input) {
    final next = _maybeNext();
    return next == null ? input : next.format(path, input);
  }

  // #docregion service-registry-maybe-resolve-after
  Formatter? _maybeNext() {
    try {
      return context.registry
          .resolveAfter<Formatter>(pluginId: pluginId, serviceId: serviceId);
    } on StateError {
      return null;
    }
  }
  // #enddocregion service-registry-maybe-resolve-after
}

/// Plugin that registers [BetterDartFormatter] as the elevated-priority winner
/// for the `code_formatter` slot. Used by the matching test to drive the
/// service through a real runtime so its `context` is bound when `format()`
/// is called.
class BetterDartFormatterPlugin extends GlobalPlugin {
  /// The plugin id for this formatter.
  static const PluginId id = PluginId('better_dart_formatter');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Formatter>(
      const ServiceId('code_formatter'),
      () => BetterDartFormatter(),
      priority: Priority.elevated,
    );
  }
}

/// Companion plugin that registers [DefaultFormatter] as the lower-priority
/// runner-up. Together with [BetterDartFormatterPlugin] this builds the
/// two-registration chain that `resolveAfter` walks past the winner to reach.
class DefaultFormatterPlugin extends GlobalPlugin {
  /// The plugin id for the default formatter.
  static const PluginId id = PluginId('default_formatter');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Formatter>(
      const ServiceId('code_formatter'),
      () => DefaultFormatter(),
      priority: Priority.normal,
    );
  }
}

// #docregion service-registry-scoped-for
void useScopedRegistry(ServiceRegistry registry) {
  final scoped = registry.scopedFor(const PluginId('my_plugin'));
  scoped.registerSingleton<AppConfig>(
    const ServiceId('config'),
    () => AppConfig.load(),
  );
}
// #enddocregion service-registry-scoped-for

// #docregion service-registry-lazy-singleton-deferred
void deferResolutionInRegister(ScopedServiceRegistry registry) {
  // (a) Lazy + closure capture; resolve when the lazy factory fires.
  registry.registerLazySingleton<AppConfig>(
    const ServiceId('config'),
    () => AppConfig.load(),
  );

  // (b) Resolve in attach or in event handlers.
}
// #enddocregion service-registry-lazy-singleton-deferred

// #docregion service-registry-enterprise-router-plugin
class EnterpriseRouterPlugin extends GlobalPlugin {
  /// The plugin id for this router.
  static const PluginId id = PluginId('enterprise_router');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerLazySingleton<ModelRouter>(
      const ServiceId('model_router'),
      () => EnterpriseRouter(ownerId: id, registryThunk: () => registry.raw),
      priority: Priority.elevated,
    );
  }
}
// #enddocregion service-registry-enterprise-router-plugin

// #docregion service-registry-resolve-basic
void getLoggerDB(PluginContext context) {
  final db = context.resolve<Database>(const ServiceId('main_db'));
  final maybeLogger = context.maybeResolve<AppConfig>(
    const ServiceId('logger'),
  );
  print('$db $maybeLogger');
}
// #enddocregion service-registry-resolve-basic

// #docregion service-registry-priority-competing
/// Two plugins register the same code_formatter slot at different priorities.
/// Higher number wins on resolution.
void registerCompetingFormatters(ServiceRegistry registry) {
  // plugin: core
  registry.registerSingleton<Formatter>(
    pluginId: const PluginId('core'),
    serviceId: const ServiceId('code_formatter'),
    create: () => DefaultFormatter(),
    priority: Priority.normal,
  );

  // plugin: my_better_formatter
  registry.registerSingleton<Formatter>(
    pluginId: const PluginId('my_better_formatter'),
    serviceId: const ServiceId('code_formatter'),
    create: () => PrettierFormatter(),
    priority: Priority.elevated,
  );
}
// #enddocregion service-registry-priority-competing

// #docregion service-registry-namespace-panel
/// Registers a namespaced panel service and resolves it.
void registerAndResolvePanel(
  ScopedServiceRegistry registry,
  PluginContext context,
) {
  const panel = Namespace('panel');

  // Build the namespaced ServiceId via call() shorthand and pass it to the
  // regular register / resolve methods.
  registry.registerSingleton<PanelWidgetFactory>(
    panel('console'), // ServiceId('panel.console')
    () => ConsolePanelFactory(),
  );

  final factory = context.resolve<PanelWidgetFactory>(panel('console'));
  print(factory.name);
}
// #enddocregion service-registry-namespace-panel

// #docregion service-registry-resolve-raw
/// Demonstrates resolveRaw to inspect a wrapper without instantiating.
void resolveRawExample(PluginContext context) {
  const tooling = Namespace('tooling');
  final wrapper = context.registry.resolveRaw<ModelRouter>(
    tooling('formatter'),
  );
  print(wrapper.pluginId);
  print(wrapper.priority);
  print(wrapper.capabilities);
}
// #enddocregion service-registry-resolve-raw

// #docregion service-registry-naming-register
/// Demonstrates registering a Greeter under a simple root service id.
void registerGreeter(ScopedServiceRegistry registry) {
  registry.registerSingleton<AppConfig>(
    const ServiceId('greeter'),
    () => AppConfig.load(),
  );
}
// #enddocregion service-registry-naming-register

// #docregion service-registry-naming-namespace
/// Demonstrates registering a ModelClient under a namespace.
void registerModelClient(ScopedServiceRegistry registry) {
  const agent = Namespace('agent');

  registry.registerSingleton<AppConfig>(
    agent('model'), // ServiceId('agent.model')
    () => AppConfig.load(),
  );
}
// #enddocregion service-registry-naming-namespace

/// A minimal service used in README registration examples.
abstract class ReadmeService {
  /// Performs the service action.
  void action();
}

/// A concrete implementation of [ReadmeService].
class ReadmeServiceImpl implements ReadmeService {
  @override
  void action() => print('action');
}

// #docregion service-registry-readme-registration
/// Demonstrates all three registration modes using real plugin_kit types.
void demonstrateRegistrationModes(ScopedServiceRegistry registry) {
  // Factory: new instance each resolve.
  registry.registerFactory<ReadmeService>(
    const ServiceId('my_service_factory'),
    () => ReadmeServiceImpl(),
  );

  // Singleton: same instance for every resolve.
  registry.registerSingleton<ReadmeService>(
    const ServiceId('my_service_singleton'),
    () => ReadmeServiceImpl(),
  );

  // Lazy singleton: constructed on first resolve.
  registry.registerLazySingleton<ReadmeService>(
    const ServiceId('my_service_lazy'),
    () => ReadmeServiceImpl(),
  );
}

/// Demonstrates resolving and resolveAfter from a context.
void demonstrateResolution(PluginContext context) {
  // Resolve at point of use (so hot-swaps take effect).
  final service = context.resolve<ReadmeService>(
    const ServiceId('my_service_singleton'),
  );

  // Walk the chain when you want the next-best implementation.
  final fallback = context.resolveAfter<ReadmeService>(
    pluginId: const PluginId('primary'),
    serviceId: const ServiceId('my_service_singleton'),
  );

  print('$service $fallback');
}

// #enddocregion service-registry-readme-registration
