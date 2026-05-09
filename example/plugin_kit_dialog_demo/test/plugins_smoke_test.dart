import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog_demo/plugins/all.dart';

PluginRuntime _buildRuntime({
  RuntimeSettings settings = const RuntimeSettings.empty(),
}) {
  final runtime = PluginRuntime();
  runtime.addPlugins(demoPlugins());
  runtime.init(settings: settings);
  return runtime;
}

void main() {
  test('demo plugin set has unique ids and core is locked', () {
    final plugins = demoPlugins();
    final runtime = PluginRuntime();
    addTearDown(runtime.dispose);

    expect(plugins, isNotEmpty);
    expect(plugins.map((p) => p.pluginId).toSet(), hasLength(plugins.length));

    final core = plugins.firstWhere(
      (p) => p.pluginId == const PluginId('core'),
    );
    expect(core.featureFlags.contains(FeatureFlag.locked), isTrue);

    runtime.addPlugins(plugins);
    runtime.init(settings: RuntimeSettings.empty());
  });

  test('agent.model has many competing registrations sorted by priority', () {
    final runtime = _buildRuntime();
    addTearDown(runtime.dispose);

    final registrations = runtime.globalRegistry.getRegistrations(
      const ServiceId('agent.model'),
    );
    expect(registrations, isNotNull);
    expect(
      registrations!.length,
      greaterThanOrEqualTo(4),
      reason: 'expect ≥4 stable contenders on agent.model',
    );

    final priorities = registrations
        .map((r) => r.priority)
        .toList(growable: false);
    final sorted = [...priorities]..sort((a, b) => b.compareTo(a));
    expect(
      priorities,
      sorted,
      reason: 'registrations must be returned highest-priority first',
    );

    final winner = runtime.globalRegistry.resolveRaw<Object>(
      const ServiceId('agent.model'),
    );
    expect(winner.priority, priorities.first);
  });

  test('experimental plugins carry the experimental feature flag', () {
    const experimentalIds = {
      PluginId('model_router'),
      PluginId('dart_sdk_mcp'),
      PluginId('research_agent'),
      PluginId('local_llm_runner'),
      PluginId('kagi_search'),
      PluginId('circuit_breaker'),
      PluginId('debug_overrides'),
    };

    final byId = {for (final p in demoPlugins()) p.pluginId: p};
    for (final id in experimentalIds) {
      expect(byId, contains(id), reason: '$id missing from demoPlugins');
      expect(
        byId[id]!.featureFlags.contains(FeatureFlag.experimental),
        isTrue,
        reason: id.toString(),
      );
    }
  });
}
