/// # 01: Passports and Visas
///
/// An agent presents a [ModelPassport] (model family, id, capability
/// requirements). The embassy registers one [VisaOffice] per provider; the
/// first office that can honour the passport issues a [ModelVisa] holding
/// a ready-to-use [ModelClient]. Offices that cannot serve the request
/// return null so the next candidate gets a turn.
///
/// This example registers a single provider (Anthropic), sends an Anthropic
/// passport, and uses the returned client.
library;

import 'package:model_embassy/model_embassy.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [AnthropicPlugin()])..init();
  final session = await runtime.createSession();

  // #docregion passports-and-visas-flow
  final passport = ModelPassport(
    modelFamily: 'anthropic',
    modelId: 'claude-sonnet-4-5-20250929',
  );

  final visa = await session.request<AgentBoardingCall, ModelVisa?>(
    AgentBoardingCall(passport),
  );

  final response = await visa!.client.chat('Hello from the embassy!');
  // #enddocregion passports-and-visas-flow

  print('Passport: $passport');
  print('Visa issued: $visa');
  print('Chat response: $response');

  await runtime.dispose();
}
