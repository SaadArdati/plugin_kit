import 'package:docs_snippets/plugin_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('plugin-service-basic', () {
    test('ModelRouter reads config values', () {
      final router = ModelRouter();
      router.injectSettings({'default_model': 'gpt-4o', 'temperature': 0.5});
      expect(router.defaultModel, equals('gpt-4o'));
      expect(router.temperature, closeTo(0.5, 0.001));
    });
  });

  group('plugin-service-settings-inject', () {
    test('AnthropicService reads api_key from settings', () {
      final svc = AnthropicService();
      svc.injectSettings({'api_key': 'sk-test'});
      expect(svc.apiKey, equals('sk-test'));
    });
  });

  group('stateful-plugin-service-inject-settings', () {
    test('CachedFormatter clears template on settings change', () {
      final fmt = CachedFormatter();
      fmt.compiledTemplate = 'cached';
      fmt.injectSettings({'key': 'value'});
      expect(fmt.compiledTemplate, isNull);
    });
  });

  group('migration-assistant-ready', () {
    test('AssistantRuntimeService emits AssistantReady after attach', () async {
      final plugin = _AssistantReadyPlugin();
      final runtime = PluginRuntime(plugins: [plugin])..init();
      final session = await runtime.createSession();

      AssistantReady? received;
      session.on<AssistantReady>((e) {
        received = e.event;
      });

      // Allow the async attach fire to complete.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isNotNull);
      expect(received!.assistant, isA<AssistantClient>());
      await runtime.dispose();
    });
  });

  group('migration-wait-for-assistant', () {
    test('AssistantRequestService fulfils WaitForAssistant request', () async {
      final plugin = _AssistantRequestPlugin();
      final runtime = PluginRuntime(plugins: [plugin])..init();
      final session = await runtime.createSession();

      final client = await session
          .maybeRequest<WaitForAssistant, AssistantClient>(
            const WaitForAssistant(),
          );
      expect(client, isA<AssistantClient>());
      await runtime.dispose();
    });
  });

  group('session-stateful-plugin-service', () {
    test('ChatThread is not null', () {
      final thread = ChatThread();
      expect(thread, isNotNull);
    });
  });

  group('plugin-service-settings-runtime', () {
    test('serviceSettingsExample has correct service config', () {
      final pin = const PluginId('model_router').service('decider');
      final svcSettings = serviceSettingsExample.services[pin];
      expect(svcSettings?.config['default_model'], equals('gpt-4.1-mini'));
    });
  });
}

class _AssistantReadyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('assistant_ready');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<AssistantRuntimeService>(
      const ServiceId('assistant_runtime'),
      () => AssistantRuntimeService(),
    );
  }
}

class _AssistantRequestPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('assistant_request');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<AssistantRequestService>(
      const ServiceId('assistant_request'),
      () => AssistantRequestService(),
    );
  }
}
