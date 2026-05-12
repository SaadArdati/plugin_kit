/// Cheatsheet-style symbol indexes for the plugin_kit API surface.
library;

import 'package:plugin_kit/plugin_kit.dart';

// #docregion api-cheatsheet-typed-handles-index
/// Full typed-handles index: PluginId, Namespace, ServiceId, and Pin.
void demonstrateTypedHandlesIndex() {
  const PluginId chatId = PluginId('chat');
  const Namespace agent = Namespace('agent');
  const ServiceId modelId = ServiceId('agent.model');

  // Sentinels.
  const wildcard = PluginId.wildcard;
  const winnerScoped = PluginId.winnerScoped;

  // Namespace members.
  final agentValue = agent.value;
  final systemPromptNs = agent.child('system_prompt');
  final modelIdFromNs = agent.service('model');
  final modelIdShorthand = agent('model');

  // ServiceId members.
  final modelValue = modelId.value;
  final modelNs = modelId.namespace;
  final modelLeaf = modelId.id;
  final modelTopNs = modelId.topNamespace;
  const modelNamespaced = ServiceId.namespaced(agent, 'model');

  // Pin construction via typed chain.
  final pin1 = chatId.service(modelId);
  final pin2 = PluginId.wildcard.service(modelId);
  final pin3 = const PluginId('chat').namespace('agent').service('model');
  final pin4 = const PluginId('chat').namespace('agent')('model');

  // Pin construction directly.
  final pin5 = Pin('chat', ['agent', 'model']);
  final pin6 = Pin('chat', ['greeter']);
  final pin7 = Pin.wildcard(['agent', 'tools']);

  // Pin inspection.
  final pin = Pin('chat', ['agent', 'model']);
  final pluginId = pin.pluginId;
  final serviceId = pin.serviceId;
  final isWildcard = pin.isWildcard;
  final wire = pin.wire;

  // Const-friendly wire parse.
  const constPin1 = Pin.fromWire('chat:agent.model');
  const constPin2 = Pin.fromWire('*:agent.tools');

  print(
    '$chatId $agent $modelId $wildcard $winnerScoped '
    '$agentValue $systemPromptNs $modelIdFromNs $modelIdShorthand '
    '$modelValue $modelNs $modelLeaf $modelTopNs $modelNamespaced '
    '$pin1 $pin2 $pin3 $pin4 $pin5 $pin6 $pin7 '
    '$pluginId $serviceId $isWildcard $wire '
    '$constPin1 $constPin2',
  );
}
// #enddocregion api-cheatsheet-typed-handles-index

// #docregion api-reference-typed-handles
/// Demonstrates typed handle composition.
void demonstrateTypedHandles() {
  // PluginId: identifies a plugin.
  const chatId = PluginId('chat');

  // Namespace: groups related service slots.
  const agent = Namespace('agent');

  // ServiceId: identifies a service slot.
  final modelId = agent('model');
  const directId = ServiceId('greeter');

  // Pin: pairs a plugin with a service slot.
  final pin = chatId.service(modelId);
  final wildcardPin = PluginId.wildcard.service('tools');

  print('$chatId $agent $modelId $directId $pin $wildcardPin');
}
// #enddocregion api-reference-typed-handles

// #docregion api-reference-settings
/// Full RuntimeSettings construction example.
final fullSettings = RuntimeSettings(
  plugins: {
    const PluginId('chat'): const PluginConfig(
      enabled: true,
      config: {'api_key': 'xxx'},
    ),
    const PluginId('legacy'): const PluginConfig(enabled: false),
  },
  services: {
    Pin('chat', ['agent', 'model']): const ServiceSettings(
      config: {'temperature': 0.7},
    ),

    Pin.wildcard(['agent', 'tools']): const ServiceSettings(
      priority: 200,
      config: {'verbose': true},
    ),

    Pin('legacy', ['search', 'engine']): const ServiceSettings(enabled: false),
  },
);

/// Round-trips [fullSettings] through JSON and back.
RuntimeSettings roundTripSettings() {
  final json = fullSettings.toJson();
  return RuntimeSettings.fromJson(json);
}
// #enddocregion api-reference-settings

// #docregion api-reference-request-patterns
/// Demonstrates request/response patterns on a standalone bus.
Future<void> demonstrateRequestPatterns(PluginContext context) async {
  // Nullable Response enables fall-through.
  context.bus.onRequest<SearchQuery, SearchResults?>((env) async {
    if (env.event.q.isEmpty) return null; // concede
    return const SearchResults(results: ['result']);
  });

  final response = await context.bus.request<SearchQuery, SearchResults?>(
    const SearchQuery(),
  );
  final maybe = await context.bus.maybeRequest<SearchQuery, SearchResults?>(
    const SearchQuery(),
  );
  final sync = context.bus.requestSync<SearchQuery, SearchResults?>(
    const SearchQuery(),
  );
  final maybeSync = context.bus.maybeRequestSync<SearchQuery, SearchResults?>(
    const SearchQuery(),
  );

  print('$response $maybe $sync $maybeSync');
}
// #enddocregion api-reference-request-patterns

// #docregion api-reference-bind-pattern
/// Demonstrates type-agnostic bus tap.
void demonstrateBindPattern(PluginContext context) {
  context.bus.bind((envelope) => print(envelope.event));
}

/// Plugin-form bind using the PluginHelper extension.
class BindingPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('binding_demo');

  @override
  void attach(SessionPluginContext context) {
    bind(context, (envelope) => print(envelope.event));
  }
}

/// StatefulPluginService-form bind.
class BindingService extends StatefulPluginService {
  @override
  void attach() {
    bind((envelope) => print(envelope.event));
  }
}
// #enddocregion api-reference-bind-pattern

// #docregion api-reference-scope-routing
/// Demonstrates cross-scope event routing.
class GlobalBroadcastPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('broadcaster');

  @override
  void attach(GlobalPluginContext context) {
    on<SearchQuery>(context, (env) async {
      // Broadcast to every session bus.
      await context.sessions.emit<SearchQuery>(env.event);

      // Target one session.
      if (context.sessions.isNotEmpty) {
        await context.sessions.first.bus.emit<SearchQuery>(event: env.event);
      }
    });
  }
}

/// Demonstrates a session plugin reaching the global bus.
class GlobalReachPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('global_reach');

  @override
  void attach(SessionPluginContext context) {
    on<SearchQuery>(context, (env) async {
      await context.globalBus.emit<SearchQuery>(event: env.event);
    });
  }
}
// #enddocregion api-reference-scope-routing

// #docregion service-id-getters
/// Demonstrates ServiceId namespace/id/topNamespace getters.
void demonstrateServiceIdGetters() {
  const greeter = ServiceId('greeter');
  const agentTools = ServiceId('agent.tools');

  // agentTools getters.
  final agentToolsNamespace = agentTools.namespace; // Namespace('agent')
  final agentToolsId = agentTools.id; // 'tools'
  final agentToolsTop = agentTools.topNamespace; // Namespace('agent')

  const nested = ServiceId('a.b.c');
  final nestedNamespace = nested.namespace; // Namespace('a.b')
  final nestedTop = nested.topNamespace; // Namespace('a')
  final nestedId = nested.id; // 'c'

  print(
    '$greeter $agentToolsNamespace $agentToolsId $agentToolsTop '
    '$nestedNamespace $nestedTop $nestedId',
  );
}
// #enddocregion service-id-getters

// #docregion namespace-build-service-id
/// Demonstrates building a namespaced ServiceId from a Namespace.
void demonstrateNamespaceBuild() {
  const agent = Namespace('agent');

  final tools = agent.service('tools'); // ServiceId('agent.tools')
  final model = agent('model'); // call() shorthand → ServiceId('agent.model')

  print('$tools $model');
}
// #enddocregion namespace-build-service-id

// #docregion naming-core-plugin-static-id
/// Demonstrates the canonical static const id pattern on a plugin.
class CoreNamedPlugin extends GlobalPlugin {
  /// Canonical static id for host code to reference.
  static const id = PluginId('core');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {}
}
// #enddocregion naming-core-plugin-static-id

// #docregion naming-namespace-agent-model
/// Demonstrates registering under a namespaced agent.model slot.
void registerAgentModel(ScopedServiceRegistry registry) {
  const agent = Namespace('agent');

  registry.registerSingleton<SearchResults>(
    agent('model'), // ServiceId('agent.model')
    () => const SearchResults(),
  );
}
// #enddocregion naming-namespace-agent-model

/// A search query placeholder for the reference examples.
class SearchQuery {
  /// Creates a [SearchQuery].
  const SearchQuery({this.q = ''});

  /// The query string.
  final String q;
}

/// A search result placeholder.
class SearchResults {
  /// Creates [SearchResults].
  const SearchResults({this.results = const []});

  /// The result items.
  final List<String> results;
}

/// A minimal service used in cheatsheet plugin-lifecycle examples.
class CheatsheetService {
  /// Creates a [CheatsheetService].
  const CheatsheetService();
}

/// An event used in cheatsheet examples.
class CheatsheetEvent {
  /// Creates a [CheatsheetEvent].
  const CheatsheetEvent();
}

// #docregion api-cheatsheet-plugin-lifecycle
/// Full plugin lifecycle template: dependencies, featureFlags, register,
/// attach, detach, and onPluginSettingsChanged.
class CheatsheetPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('cheatsheet_plugin');

  @override
  Set<PluginId> get dependencies => const {PluginId('other_plugin')};

  @override
  List<FeatureFlag> get featureFlags => const []; // .experimental, .locked

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<CheatsheetService>(
      const ServiceId('cheatsheet'),
      () => const CheatsheetService(),
    );
  }

  @override
  void attach(SessionPluginContext context) {
    on<CheatsheetEvent>(context, (e) {
      print('received: ${e.event.runtimeType}');
    });
  }

  @override
  Future<void> detach(SessionPluginContext context) async {}

  @override
  Future<void> onPluginSettingsChanged(
    SessionPluginContext oldContext,
    SessionPluginContext newContext,
  ) async {}
}
// #enddocregion api-cheatsheet-plugin-lifecycle

/// A second plugin used to demonstrate [PluginRuntime.addPlugin] without
/// colliding with [CheatsheetPlugin]'s id.
class ExtraCheatsheetPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('extra_cheatsheet_plugin');

  @override
  void register(ScopedServiceRegistry registry) {}
}

// #docregion api-cheatsheet-configurable-capability
/// A configurable capability marker used in capability-pattern examples.
class ConfigurableCapabilityCheatsheet extends Capability {
  /// Creates a [ConfigurableCapabilityCheatsheet].
  const ConfigurableCapabilityCheatsheet();
}

/// Registers [CheatsheetService] with a [ConfigurableCapabilityCheatsheet] and
/// verifies it with [resolveRaw].
void registerAndCheckConfigurable(
  ScopedServiceRegistry registry,
  ServiceRegistry raw,
) {
  registry.registerSingleton<CheatsheetService>(
    const ServiceId('cheatsheet'),
    () => const CheatsheetService(),
    capabilities: const {ConfigurableCapabilityCheatsheet()},
  );

  final hasIt = raw
      .resolveRaw<CheatsheetService>(const ServiceId('cheatsheet'))
      .capabilities
      .hasType<ConfigurableCapabilityCheatsheet>();
  print('configurable: $hasIt');
}
// #enddocregion api-cheatsheet-configurable-capability

// #docregion api-cheatsheet-plugin-service-classes
/// A settings-aware model-routing service.
class CheatsheetModelRouter extends PluginService {
  /// The default model name read from injected settings.
  String get defaultModel => config.getString('default_model') ?? 'gpt-4';

  /// Reacts to settings changes by invalidating any cached state.
  @override
  void onSettingsInjected() {
    // Invalidate cached model selection on settings change.
    cachedModel = defaultModel;
  }

  /// The cached effective model name, refreshed on each settings injection.
  String cachedModel = 'gpt-4';
}

/// A stateful service that subscribes to [CheatsheetEvent] while attached.
class CheatsheetStatefulService extends StatefulPluginService {
  @override
  void attach() {
    on<CheatsheetEvent>((e) {
      print('stateful: ${e.event.runtimeType}');
    });
  }

  @override
  Future<void> detach() async {}
}
// #enddocregion api-cheatsheet-plugin-service-classes

// #docregion api-cheatsheet-runtime-session-pattern
/// Demonstrates the full runtime → session lifecycle with a custom context.
Future<void> demonstrateRuntimeSessionPattern() async {
  final runtime = PluginRuntime(plugins: [CheatsheetPlugin()]);
  runtime.init(settings: const RuntimeSettings.empty());

  final session = await runtime.createSession(
    settings: const RuntimeSettings.empty(),
    contextFactory: (registry, sessionBus, globalBus) => SessionPluginContext(
      registry: registry,
      bus: sessionBus,
      globalBus: globalBus,
    ),
  );

  print('enabled: ${session.enabledPluginIds}');
  print('sessions: ${runtime.sessions.length}');
  print('globalRegistry: ${runtime.globalRegistry.runtimeType}');
  print('globalBus: ${runtime.globalBus.runtimeType}');

  await session.dispose();
  await runtime.dispose();
}
// #enddocregion api-cheatsheet-runtime-session-pattern

// #docregion api-cheatsheet-context-stubs
/// Demonstrates the three stub constructors for unit tests.
void demonstrateContextStubs() {
  final base = PluginContext.stub();
  final global = GlobalPluginContext.stub();
  final session = SessionPluginContext.stub();

  print('base: ${base.runtimeType}');
  print('global: ${global.runtimeType}');
  print('session: ${session.runtimeType}');
}
// #enddocregion api-cheatsheet-context-stubs

// #docregion api-cheatsheet-runtime-api
/// Demonstrates the runtime management API surface.
Future<void> demonstrateRuntimeApi() async {
  final runtime = PluginRuntime(plugins: [CheatsheetPlugin()]);
  runtime.init(
    settings: const RuntimeSettings.empty(),
    defaultEnabledPluginIds: null,
    // null: all on except experimental; non-null: only listed are on
  );

  print(runtime.settings);
  print(runtime.settingsStream.runtimeType);

  print(runtime.enabledPlugins.toList());
  print(runtime.enabledPluginIds);
  print(runtime.isPluginEnabled(const PluginId('cheatsheet_plugin')));

  print(runtime.attachedPlugins);
  print(runtime.attachedPluginIds);
  print(runtime.isPluginAttached(const PluginId('cheatsheet_plugin')));

  runtime.addPlugin(ExtraCheatsheetPlugin());
  runtime.addPlugins([]);

  final session = await runtime.createSession();
  await runtime.updateSettings(const RuntimeSettings.empty());
  runtime.updateSettingsSnapshot(const RuntimeSettings.empty());
  runtime.resetSettings();

  await session.dispose();
  await runtime.dispose();
}
// #enddocregion api-cheatsheet-runtime-api

// #docregion api-cheatsheet-valid-plugin-ids
/// Demonstrates valid [PluginId] naming conventions.
void demonstrateValidPluginIds() {
  const fine1 = PluginId('chat');
  const fine2 = PluginId('my_internal');
  const fine3 = PluginId('_my_internal');
  // single-underscore is fine; only '__pk_' prefix is reserved.
  print('$fine1 $fine2 $fine3');
}
// #enddocregion api-cheatsheet-valid-plugin-ids

// #docregion testing-context-stub-inject
/// Demonstrates injecting a stub service into [SessionPluginContext.stub].
void demonstrateContextStubInject() {
  final ctx = SessionPluginContext.stub();
  ctx.registry.registerSingleton<CheatsheetService>(
    pluginId: const PluginId('test'),
    serviceId: const ServiceId('cheatsheet'),
    create: () => const CheatsheetService(),
    priority: Priority.system,
  );
  final svc = ctx.resolve<CheatsheetService>(const ServiceId('cheatsheet'));
  print('resolved: ${svc.runtimeType}');
}

// #enddocregion testing-context-stub-inject
