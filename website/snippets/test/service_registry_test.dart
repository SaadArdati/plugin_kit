import 'package:docs_snippets/service_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';

void main() {
  group('service-registry-register-all-three', () {
    test('all three registration styles work', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('my_plugin'));
      registerAllThree(scoped);

      expect(
        registry.maybeResolve<QueryBuilder>(const ServiceId('query_builder')),
        isNotNull,
      );
      expect(
        registry.maybeResolve<Database>(const ServiceId('main_db')),
        isNotNull,
      );
      expect(
        registry.maybeResolve<AppConfig>(const ServiceId('config')),
        isNotNull,
      );
    });
  });

  group('service-registry-priority', () {
    test('higher priority registration wins', () {
      final registry = ServiceRegistry();
      registerWithPriority(registry);
      final formatter = registry.resolve<Formatter>(
        const ServiceId('code_formatter'),
      );
      expect(formatter, isA<PrettierFormatter>());
    });
  });

  group('service-registry-namespace', () {
    test('namespace shorthand produces correct service id', () {
      final registry = ServiceRegistry();
      final scoped = registry.scopedFor(const PluginId('terminal_plugin'));
      registerNamespacedService(scoped);

      final context = PluginContext.stub(registry: registry);
      final factory = resolveNamespaced(context);
      expect(factory, isNotNull);
    });
  });

  group('service-registry-settings-injection', () {
    test('AnthropicService reads config from injected settings', () {
      final svc = AnthropicService();
      svc.injectSettings({'api_key': 'key-1', 'temperature': 0.9});
      expect(svc.apiKey, equals('key-1'));
      expect(svc.temperature, closeTo(0.9, 0.001));
    });
  });

  group('service-registry-scoped-for', () {
    test('scoped registry writes to raw registry', () {
      final registry = ServiceRegistry();
      useScopedRegistry(registry);
      expect(
        registry.maybeResolve<AppConfig>(const ServiceId('config')),
        isNotNull,
      );
    });
  });

  group('service-registry-resolve-after', () {
    test('BetterDartFormatter handles .dart, delegates other files', () async {
      final runtime = PluginRuntime(
        plugins: [DefaultFormatterPlugin(), BetterDartFormatterPlugin()],
      )..init();

      final formatter = runtime.globalRegistry.resolve<Formatter>(
        const ServiceId('code_formatter'),
      );
      expect(formatter, isA<BetterDartFormatter>());
      expect(formatter.format('app.dart', '  let x = 1  '), 'let x = 1');
      expect(formatter.format('notes.txt', '  hello  '), '  hello  ');

      await runtime.dispose();
    });
  });

  group('service-registry-enterprise-router-plugin', () {
    test('enterprise router plugin registers under model_router', () async {
      final runtime = PluginRuntime(plugins: [EnterpriseRouterPlugin()])
        ..init();
      final router = runtime.globalRegistry.resolve<ModelRouter>(
        const ServiceId('model_router'),
      );
      expect(router, isNotNull);
      expect(router.routeFor('enterprise query'), contains('enterprise'));
      await runtime.dispose();
    });
  });
}
