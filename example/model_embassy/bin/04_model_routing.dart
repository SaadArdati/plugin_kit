/// # 04: Model Routing
///
/// Event mutation in action. A router plugin subscribes to
/// [PrepareResponseEvent] at priority 0 and rewrites `event.passport` based
/// on prompt length. Later handlers (and the caller that emitted the event)
/// see the mutated passport.
///
/// Short prompts under 100 chars are routed to a lightweight Haiku model.
/// Long prompts keep their originally requested Sonnet model. The visa
/// office processes the boarding call without knowing routing happened.
library;

import 'package:model_embassy/model_embassy.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Intercepts [PrepareResponseEvent] and swaps the passport for short prompts.
class ModelRouterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('model_router');

  @override
  void attach(SessionPluginContext context) {
    context.bus.on<PrepareResponseEvent>((envelope) async {
      final event = envelope.event;
      final originalPassport = event.passport;

      print('  [Router] Prompt length: ${event.prompt.length} chars');
      print('  [Router] Requested model: ${originalPassport.modelId}');

      if (event.prompt.length < 100) {
        // Short prompt: downgrade to the lightweight model.
        final cheaperPassport = ModelPassport(
          modelFamily: 'anthropic',
          modelId: 'claude-haiku-4-5-20251001',
          requiredCapabilities: originalPassport.requiredCapabilities,
          minContextWindow: originalPassport.minContextWindow,
        );
        event.passport = cheaperPassport;
        print(
          '  [Router] Short prompt detected: routing to lighter model: '
          '${cheaperPassport.modelId}',
        );
      } else {
        // Long prompt: keep the original model.
        print(
          '  [Router] Long prompt: keeping original model: '
          '${originalPassport.modelId}',
        );
      }
    }, priority: 0);
  }
}

// ---------------------------------------------------------------------------
// Helper: run one boarding scenario
// ---------------------------------------------------------------------------

Future<void> _runScenario(
  PluginSession session,
  String label,
  String prompt,
  ModelPassport requestedPassport,
) async {
  print('\n--- $label ---');
  print('Prompt: "$prompt"');
  print('Initial passport: $requestedPassport');

  // Step 1: emit the preparation event so routers can mutate the passport.
  final prepEvent = PrepareResponseEvent(
    passport: requestedPassport,
    prompt: prompt,
  );
  await session.emit(prepEvent);

  // Step 2: use the (possibly mutated) passport for the actual boarding call.
  final finalPassport = prepEvent.passport;
  print('Final passport after routing: $finalPassport');

  final visa = await session.request<AgentBoardingCall, ModelVisa?>(
    AgentBoardingCall(finalPassport),
  );

  print('Visa issued: $visa');

  final response = await visa!.client.chat(prompt);
  print('Response: $response');
}

Future<void> main() async {
  // Register the router alongside the provider so it can mutate passports
  // before the visa office sees the boarding call.
  final runtime = PluginRuntime(
    plugins: [ModelRouterPlugin(), AnthropicPlugin()],
  )..init();
  final session = await runtime.createSession();

  final defaultPassport = ModelPassport(
    modelFamily: 'anthropic',
    modelId: 'claude-sonnet-4-5-20250929',
  );

  // Scenario A: short prompt, routed to the lighter model.
  await _runScenario(
    session,
    'Scenario A: short prompt',
    'Hello!',
    defaultPassport,
  );

  // Scenario B: long prompt, keeps the originally requested model.
  await _runScenario(
    session,
    'Scenario B: long prompt',
    'Please analyse the following multi-document corpus and produce a detailed '
        'thematic summary covering the principal arguments, evidence, and '
        'counterarguments presented across all sources.',
    defaultPassport,
  );

  await runtime.dispose();
}
