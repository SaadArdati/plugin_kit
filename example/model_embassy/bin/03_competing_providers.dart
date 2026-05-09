/// # 03: Competing Providers
///
/// Multiple visa offices, one per model family, each registered at a
/// different priority. An [AgentBoardingCall] propagates through the
/// offices in priority order until one claims it. If all concede, the
/// request goes unanswered.
///
/// Three providers registered here:
/// - Anthropic (priority 100): serves the `anthropic` family.
/// - OpenAI (priority 80): serves the `openai` family.
/// - Ollama (priority 50): serves `meta`, `mistral`, and `ollama`.
///
/// Main presents four passports (one per family + one unknown) and prints
/// which office claimed each. The unknown passport uses `maybeRequest` so
/// the unclaimed case returns null instead of throwing.
library;

import 'package:model_embassy/model_embassy.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [AnthropicPlugin(), OpenAIPlugin(), OllamaPlugin()],
  )..init();
  final session = await runtime.createSession();

  final passports = [
    ModelPassport(
      modelFamily: 'anthropic',
      modelId: 'claude-sonnet-4-5-20250929',
    ),
    ModelPassport(modelFamily: 'openai', modelId: 'gpt-4o'),
    ModelPassport(modelFamily: 'meta', modelId: 'llama-3'),
    ModelPassport(modelFamily: 'unknown', modelId: 'mystery-model'),
  ];

  final results = <(ModelPassport, ModelVisa?)>[];

  for (final passport in passports) {
    if (passport.modelFamily == 'unknown') {
      // When no provider can serve a passport, maybeRequest returns null
      // rather than throwing an unhandled-request error.
      final visa = await session.maybeRequest<AgentBoardingCall, ModelVisa?>(
        AgentBoardingCall(passport),
      );
      results.add((passport, visa));
    } else {
      final visa = await session.request<AgentBoardingCall, ModelVisa?>(
        AgentBoardingCall(passport),
      );
      results.add((passport, visa));
    }
  }

  print(
    '╔══════════════════════════════════════════════════════════════════════╗',
  );
  print(
    '║                    Model Embassy: Boarding Results                 ║',
  );
  print(
    '╠══════════════════════╦═══════════════════════════════╦══════════════╣',
  );
  print(
    '║ Family               ║ Model ID                      ║ Provider     ║',
  );
  print(
    '╠══════════════════════╬═══════════════════════════════╬══════════════╣',
  );

  for (final (passport, visa) in results) {
    final family = passport.modelFamily.padRight(20);
    final modelId = passport.modelId.padRight(29);
    final provider = (visa?.provider ?? '(none)').padRight(12);
    print('║ $family ║ $modelId ║ $provider ║');
  }

  print(
    '╚══════════════════════╩═══════════════════════════════╩══════════════╝',
  );

  print('');

  // Show that the claimed visas carry working clients.
  for (final (passport, visa) in results) {
    if (visa == null) {
      print('${passport.modelFamily}/${passport.modelId}: no visa issued');
    } else {
      final response = await visa.client.chat('Hello!');
      print('${passport.modelFamily}/${passport.modelId}: $response');
    }
  }

  await runtime.dispose();
}
