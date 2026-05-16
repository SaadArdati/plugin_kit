/// Snippets for RuntimeSettings, PluginConfig, ServiceSettings, Pin, and
/// their fromJson/toJson round-trip.
library;

import 'package:plugin_kit/plugin_kit.dart';

// #docregion runtime-settings-construct
final settings = RuntimeSettings(
  plugins: {
    const PluginId('sql_language'): const PluginConfig(enabled: true),
    const PluginId('experimental_router'): const PluginConfig(enabled: false),
  },
  services: {
    const PluginId('linter_suite').service('line_length_linter'):
        const ServiceSettings(config: {'max_line_length': 120}),
    PluginId.wildcard.service('agent_service'): const ServiceSettings(
      priority: 200,
      config: {'provider': 'openai'},
    ),
  },
);
// #enddocregion runtime-settings-construct

// #docregion runtime-settings-json
final settingsForJson = RuntimeSettings(
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

Map<String, dynamic> roundTripJson() {
  final json = settingsForJson.toJson();
  final back = RuntimeSettings.fromJson(json);
  assert(back.plugins.length == settingsForJson.plugins.length);
  return json;
}
// #enddocregion runtime-settings-json

// #docregion runtime-settings-to-json
void demonstrateToJson() {
  final json = settings.toJson();
  final restored = RuntimeSettings.fromJson(json);
  assert(restored.plugins.length == settings.plugins.length);
}
// #enddocregion runtime-settings-to-json

// #docregion runtime-settings-priority
final settingsWithPriority = RuntimeSettings(
  plugins: {const PluginId('formal'): const PluginConfig(enabled: false)},
  services: {
    Pin('chat', ['agent', 'model']): const ServiceSettings(
      config: {'temperature': 0.7},
    ),
    Pin.wildcard(['agent', 'tools']): const ServiceSettings(priority: 200),
  },
);
// #enddocregion runtime-settings-priority

// #docregion runtime-settings-copy-with
RuntimeSettings updateAnalyticsEnabled(RuntimeSettings current, bool enabled) {
  return current.copyWith(
    plugins: {
      ...current.plugins,
      const PluginId('analytics'): PluginConfig(enabled: enabled),
    },
  );
}
// #enddocregion runtime-settings-copy-with

// #docregion service-settings-copy-with
ServiceSettings withDisabledService(ServiceSettings original) {
  return original.copyWith(enabled: false);
}
// #enddocregion service-settings-copy-with

// #docregion plugin-config-construct
const pluginConfig = PluginConfig(
  enabled: true,
  config: {'api_key': 'sk-demo'},
);
// #enddocregion plugin-config-construct

// #docregion runtime-settings-empty
const emptySettings = RuntimeSettings();
// #enddocregion runtime-settings-empty

// #docregion runtime-settings-wildcard-follows-winner
/// Two plugins both register `model_router`. The wildcard supplies
/// `temperature: 0.5`; the plugin-specific entry on `beta` only bumps
/// priority. Result: `beta` is now the winning registration, and it
/// resolves with `temperature: 0.5` from the wildcard. The wildcard
/// targets the slot, not a plugin, so it follows whichever registration
/// currently wins.
final wildcardFollowsWinner = RuntimeSettings(
  services: {
    PluginId.wildcard.service('model_router'): const ServiceSettings(
      config: {'temperature': 0.5},
    ),
    const PluginId('beta').service('model_router'): const ServiceSettings(
      priority: 200,
    ),
  },
);
// #enddocregion runtime-settings-wildcard-follows-winner

// #docregion runtime-settings-pin-json
/// Demonstrates constructing [RuntimeSettings] with [Pin] keys and
/// performing a JSON round-trip.
RuntimeSettings demonstrateSettingsWithPin() {
  final settings = RuntimeSettings(
    plugins: {const PluginId('formal'): const PluginConfig(enabled: false)},
    services: {
      Pin('chat', ['agent', 'model']): const ServiceSettings(
        config: {'temperature': 0.7},
      ),
      Pin.wildcard(['agent', 'tools']): const ServiceSettings(priority: 200),
    },
  );

  // JSON round-trip preserves the wire format ("chat:agent.model", "*:agent.tools").
  final json = settings.toJson();
  final back = RuntimeSettings.fromJson(json);
  return back;
}
// #enddocregion runtime-settings-pin-json

// #docregion service-settings-clear-priority
/// The correct way to clear a priority override on [ServiceSettings].
///
/// [copyWith(priority: null)] keeps the existing priority because the
/// implementation uses [??]. Use [ServiceSettings.withClearedPriority].
ServiceSettings clearPriority(ServiceSettings existing) {
  return existing.withClearedPriority();
}
// #enddocregion service-settings-clear-priority

// #docregion runtime-settings-json-roundtrip
/// Demonstrates the JSON round-trip assertion.
void demonstrateJsonRoundtrip() {
  const settings = RuntimeSettings(
    plugins: {
      PluginId('main_agent'): PluginConfig(enabled: true),
      PluginId('experimental_router'): PluginConfig(enabled: false),
    },
  );
  final restored = RuntimeSettings.fromJson(settings.toJson());
  assert(settings == restored);
}
// #enddocregion runtime-settings-json-roundtrip

// #docregion pin-from-wire
/// Demonstrates Pin.fromWire parsing a wire-format key.
void demonstratePinFromWire() {
  const pin = Pin.fromWire('main_agent:agent.temperature');
  // pin.pluginId  == PluginId('main_agent')
  // pin.serviceId == ServiceId('agent.temperature')
  // pin.wire      == 'main_agent:agent.temperature'
  print('${pin.pluginId} ${pin.serviceId} ${pin.wire}');
}
// #enddocregion pin-from-wire

// #docregion config-node-list-map
/// Demonstrates list and map() on a ConfigNode.
void demonstrateConfigNodeListMap() {
  const node = ConfigNode({
    'tools': ['hammer', 'wrench'],
    'headers': {'timeout_ms': 5000},
  });
  final tools = node.list<String>('tools') ?? const [];
  final headers = node.map('headers') ?? const {};
  final timeoutMs = headers['timeout_ms'] as int?;
  print('$tools $timeoutMs');
}
// #enddocregion config-node-list-map

/// Demonstrates config.raw for untyped passthrough.
void demonstrateConfigNodeRaw() {
  // #docregion config-node-raw
  const node = ConfigNode({
    'advanced_payload': {'nested': true},
  });
  final payload = node.raw('advanced_payload');
  print(payload);
  // #enddocregion config-node-raw
}

// #docregion config-node-defaults
/// Demonstrates applying defaults via ?? at the call site.
void demonstrateConfigNodeDefaults() {
  const node = ConfigNode({
    'temperature': 0.4,
    'tools': ['search'],
  });
  final temperature = node.getDouble('temperature') ?? 0.7;
  final tools = node.list<String>('tools') ?? const [];
  final provider = node.getString('provider') ?? 'openai';
  print('$temperature $tools $provider');
}
// #enddocregion config-node-defaults

// #docregion config-node-map-access
/// Demonstrates reading a nested map with map() then indexing.
void demonstrateNestedMapAccess() {
  const node = ConfigNode({
    'headers': {'timeout_ms': 3000},
  });
  final headers = node.map('headers') ?? const {};
  final timeoutMs = headers['timeout_ms'] as int?;
  print(timeoutMs);
}

// #enddocregion config-node-map-access
