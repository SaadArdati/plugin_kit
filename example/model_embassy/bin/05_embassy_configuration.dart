/// # 05: Embassy Configuration
///
/// [ServiceSettings] plus [ConfigNode] inject per-session configuration into
/// a [StatefulPluginService]. Three sessions share one runtime and one
/// registered visa office, but each reads different `api_key`, `base_url`,
/// and `default_model` values from the settings it was created with.
///
/// Session A: production credentials (scoped key).
/// Session B: staging credentials (scoped key).
/// Session C: wildcard key (`*:visa_office`) that targets whatever plugin
/// owns the `visa_office` slot, no plugin id needed.
library;

import 'package:model_embassy/model_embassy.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Visa office that reads its credentials from injected `config`.
/// Each session's `register()` pass constructs a fresh
/// [ConfigurableVisaOffice], and that session's settings configure it
/// independently.
class ConfigurableVisaOffice extends SessionStatefulPluginService {
  @override
  void attach() {
    // Config is populated before attach() is called, so it is safe to read
    // here. In a real implementation you would use these values to configure
    // an HTTP client or SDK instance.
    final apiKey = config.getString('api_key') ?? '(not configured)';
    final baseUrl = config.getString('base_url') ?? '(not configured)';
    final defaultModel =
        config.getString('default_model') ?? 'claude-sonnet-4-5-20250929';

    print('  [ConfigurableVisaOffice] Attached with config:');
    print('    api_key      = $apiKey');
    print('    base_url     = $baseUrl');
    print('    default_model= $defaultModel');

    onRequest<AgentBoardingCall, ModelVisa>((req) async {
      final passport = req.event.passport;

      if (passport.modelFamily != 'anthropic') return null;

      // In production this would use api_key + base_url to construct a real client.
      // Here we demonstrate that config values were successfully injected.
      final resolvedModel = passport.modelId.isNotEmpty
          ? passport.modelId
          : defaultModel;

      print(
        '  [ConfigurableVisaOffice] Issuing visa for $resolvedModel '
        '(api_key ends with: ...${apiKey.length > 4 ? apiKey.substring(apiKey.length - 4) : apiKey})',
      );

      final client = AnthropicClient(modelId: resolvedModel);
      return ModelVisa(
        passport: passport,
        provider: client.providerName,
        client: client,
      );
    });
  }
}

class ConfiguredProviderPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('configured_provider');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<ConfigurableVisaOffice>(
      const ServiceId('visa_office'),
      () => ConfigurableVisaOffice(),
      priority: 100,
    );
  }
}

Future<void> _board(PluginSession session, String label) async {
  print('\n  Boarding call from: $label');
  final passport = ModelPassport(
    modelFamily: 'anthropic',
    modelId: 'claude-sonnet-4-5-20250929',
  );
  final visa = await session.maybeRequest<AgentBoardingCall, ModelVisa>(
    AgentBoardingCall(passport),
  );
  if (visa == null) {
    print('  No visa issued for $label.');
    return;
  }
  final response = await visa.client.chat('Hello from $label');
  print('  Response: $response');
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [ConfiguredProviderPlugin()])..init();

  print('=== Session A: production credentials ===\n');

  final sessionA = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin('configured_provider', ['visa_office']): ServiceSettings(
          config: {
            'api_key': 'sk-mock-anthropic-key-12345',
            'base_url': 'https://api.anthropic.com/v1',
            'default_model': 'claude-sonnet-4-5-20250929',
          },
        ),
      },
    ),
  );

  await _board(sessionA, 'Session A');
  await sessionA.dispose();

  print('\n=== Session B: staging credentials ===\n');

  final sessionB = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin('configured_provider', ['visa_office']): ServiceSettings(
          config: {
            'api_key': 'sk-staging-key-99999',
            'base_url': 'https://staging.anthropic.com/v1',
            'default_model': 'claude-haiku-4-5-20251001',
          },
        ),
      },
    ),
  );

  await _board(sessionB, 'Session B');
  await sessionB.dispose();

  print('\n=== Session C: wildcard override (*:visa_office) ===\n');

  final sessionC = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin.wildcard(['visa_office']): ServiceSettings(
          config: {
            'api_key': 'sk-wildcard-key-00001',
            'base_url': 'https://api.anthropic.com/v1',
            'default_model': 'claude-sonnet-4-5-20250929',
          },
        ),
      },
    ),
  );

  await _board(sessionC, 'Session C (wildcard)');
  await sessionC.dispose();

  await runtime.dispose();
}
