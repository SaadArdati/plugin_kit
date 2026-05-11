import 'package:docs_snippets/api_reference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('api-cheatsheet-typed-handles-index', () {
    test('demonstrateTypedHandlesIndex runs without error', () {
      demonstrateTypedHandlesIndex();
    });

    test('Pin wire format matches expectation', () {
      const pin = Pin.fromWire('chat:agent.model');
      expect(pin.wire, equals('chat:agent.model'));
      expect(pin.pluginId, equals(const PluginId('chat')));
      expect(pin.serviceId, equals(const ServiceId('agent.model')));
      expect(pin.isWildcard, isFalse);
    });

    test('wildcard Pin is marked as wildcard', () {
      const wpin = Pin.fromWire('*:agent.tools');
      expect(wpin.isWildcard, isTrue);
    });
  });

  group('api-reference-typed-handles', () {
    test('demonstrateTypedHandles runs without error', () {
      demonstrateTypedHandles();
    });
  });

  group('api-reference-settings', () {
    test('fullSettings has two plugin entries', () {
      expect(fullSettings.plugins, hasLength(2));
      expect(fullSettings.plugins.containsKey(const PluginId('chat')), isTrue);
    });

    test('roundTripSettings produces equivalent settings', () {
      final rt = roundTripSettings();
      expect(rt.plugins, hasLength(2));
      expect(rt.services, hasLength(3));
    });
  });

  group('api-reference-bind-pattern', () {
    test('BindingPlugin has correct pluginId', () {
      expect(BindingPlugin().pluginId, equals(const PluginId('binding_demo')));
    });
  });

  group('api-reference-scope-routing', () {
    test('GlobalBroadcastPlugin has correct pluginId', () {
      expect(
        GlobalBroadcastPlugin().pluginId,
        equals(const PluginId('broadcaster')),
      );
    });

    test('GlobalReachPlugin has correct pluginId', () {
      expect(
        GlobalReachPlugin().pluginId,
        equals(const PluginId('global_reach')),
      );
    });
  });

  group('api-cheatsheet-plugin-lifecycle', () {
    test('CheatsheetPlugin has expected pluginId and dependencies', () async {
      final plugin = CheatsheetPlugin();
      expect(plugin.pluginId, equals(const PluginId('cheatsheet_plugin')));
      expect(plugin.dependencies, contains(const PluginId('other_plugin')));
      expect(plugin.featureFlags, isEmpty);
    });
  });

  group('api-cheatsheet-configurable-capability', () {
    test('registerAndCheckConfigurable finds the capability', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('test_plugin'));
      registerAndCheckConfigurable(scoped, registry);
    });
  });

  group('api-cheatsheet-plugin-service-classes', () {
    test('CheatsheetModelRouter reads default model from settings', () {
      final service = CheatsheetModelRouter();
      service.injectSettings({'default_model': 'claude-opus-4-7'}, hash: 'h1');
      expect(service.defaultModel, equals('claude-opus-4-7'));
      expect(service.cachedModel, equals('claude-opus-4-7'));
    });
  });

  group('api-cheatsheet-runtime-session-pattern', () {
    test('demonstrateRuntimeSessionPattern completes without error', () async {
      await expectLater(demonstrateRuntimeSessionPattern(), completes);
    });
  });

  group('api-cheatsheet-context-stubs', () {
    test('demonstrateContextStubs runs without error', () {
      demonstrateContextStubs();
    });
  });

  group('api-cheatsheet-runtime-api', () {
    test('demonstrateRuntimeApi completes without error', () async {
      await expectLater(demonstrateRuntimeApi(), completes);
    });
  });

  group('api-cheatsheet-valid-plugin-ids', () {
    test('demonstrateValidPluginIds runs without error', () {
      demonstrateValidPluginIds();
    });
  });

  group('testing-context-stub-inject', () {
    test('demonstrateContextStubInject resolves the injected service', () {
      demonstrateContextStubInject();
    });
  });
}
