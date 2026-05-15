import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _AlphaService extends PluginService {}

class _AlphaPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_AlphaService>(
      const ServiceId('agent.model'),
      () => _AlphaService(),
    );
  }
}

void main() {
  group('bug-hunt iter 11: init-logandskip-retains-unknown-service-pin', () {
    test(
      'drops unknown plugin-scoped service pins from settings and overrides under logAndSkip',
      () {
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
        addTearDown(runtime.dispose);
        final badPin = Pin('alpha', ['agent', 'renamed_in_v2']);

        runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.logAndSkip,
          settings: RuntimeSettings(
            services: {badPin: const ServiceSettings(config: {'k': 'v'})},
          ),
        );

        expect(runtime.settings.services.containsKey(badPin), isFalse);
        expect(
          runtime.globalRegistry.overrides.any(
            (o) =>
                o.plugin == const PluginId('alpha') &&
                o.serviceId == const ServiceId('agent.renamed_in_v2'),
          ),
          isFalse,
        );
      },
    );
  });
}
