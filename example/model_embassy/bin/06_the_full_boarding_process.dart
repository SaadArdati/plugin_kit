/// # 06: Full Boarding Process
///
/// All three provider plugins register in one runtime. Three agents with
/// distinct capability requirements each present a passport; the priority
/// cascade (Anthropic 100, OpenAI 80, Ollama 50) routes each to the first
/// office that can serve it. The returned visa carries a ready-to-use
/// client.
library;

import 'package:model_embassy/model_embassy.dart';
import 'package:plugin_kit/plugin_kit.dart';

class AgentSpec {
  final String name;
  final ModelPassport passport;

  const AgentSpec({required this.name, required this.passport});
}

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [AnthropicPlugin(), OpenAIPlugin(), OllamaPlugin()],
  )..init();
  final session = await runtime.createSession();

  final agents = [
    AgentSpec(
      name: 'Chat Agent',
      passport: ModelPassport(
        modelFamily: 'anthropic',
        modelId: 'claude-sonnet-4-5-20250929',
        requiredCapabilities: {ModelCapability.streaming},
      ),
    ),
    AgentSpec(
      name: 'Vision Agent',
      passport: ModelPassport(
        modelFamily: 'openai',
        modelId: 'gpt-4o',
        requiredCapabilities: {ModelCapability.vision},
      ),
    ),
    AgentSpec(
      name: 'Code Agent',
      passport: ModelPassport(
        modelFamily: 'anthropic',
        modelId: 'claude-sonnet-4-5-20250929',
        requiredCapabilities: {
          ModelCapability.toolUse,
          ModelCapability.codeExecution,
        },
      ),
    ),
  ];

  print('=== Boarding all agents ===\n');

  final results = <(AgentSpec, ModelVisa?)>[];

  for (final agent in agents) {
    print('--- ${agent.name} ---');
    print(
      'Passport: ${agent.passport.modelFamily}/${agent.passport.modelId}  '
      '(needs: ${_capabilitiesLabel(agent.passport.requiredCapabilities)})',
    );

    final visa = await session.maybeRequest<AgentBoardingCall, ModelVisa>(
      AgentBoardingCall(agent.passport),
    );

    if (visa == null) {
      print('No provider claimed this passport.\n');
    } else {
      print('Provider: ${visa.provider}');
      final prompt = _promptFor(agent.name);
      final response = await visa.client.chat(prompt);
      print('Response: $response\n');
    }

    results.add((agent, visa));
  }

  print('=== Boarding Summary ===\n');

  for (final (agent, visa) in results) {
    final caps = _capabilitiesLabel(agent.passport.requiredCapabilities);
    if (visa == null) {
      print('  ${agent.name.padRight(14)} → (no provider)');
    } else {
      final routing = '${visa.provider} / ${visa.passport.modelId}';
      print(
        '  ${agent.name.padRight(14)} → ${routing.padRight(46)}  (needs: $caps)',
      );
    }
  }

  print('');

  await runtime.dispose();
}

String _capabilitiesLabel(Set<ModelCapability> caps) {
  if (caps.isEmpty) return '(none)';
  return caps.map((c) => c.name).join(', ');
}

String _promptFor(String agentName) {
  switch (agentName) {
    case 'Chat Agent':
      return 'Summarise the key ideas behind large language models in two sentences.';
    case 'Vision Agent':
      return 'Describe what you see in the attached image.';
    case 'Code Agent':
      return 'Write a Dart function that reverses a list in place.';
    default:
      return 'Hello.';
  }
}
