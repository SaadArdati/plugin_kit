/// # 02: The Visa Office
///
/// A [VisaOffice] is a [StatefulPluginService]. It attaches on session start
/// and listens for [AgentBoardingCall] requests. Each request: check the
/// passport's model family against the office's supported families. Match
/// claims by building a client and returning a [ModelVisa]. No match
/// concedes (returns null) so the next office can try.
///
/// [VerboseVisaOffice] narrates each decision so the claim/concede flow is
/// visible. Main presents one recognised passport and one unknown passport
/// to show both branches.
library;

import 'package:model_embassy/model_embassy.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// A visa office that prints each step of its review.
class VerboseVisaOffice extends VisaOffice {
  @override
  Set<String> get supportedFamilies => {'anthropic'};

  @override
  ModelClient createClient(ModelPassport passport) =>
      AnthropicClient(modelId: passport.modelId);

  @override
  void attach() {
    // This override intentionally does not call super.attach(); it installs a
    // single verbose handler so every claim/concede decision is visible.
    print('  [Visa Office] Attached and listening for boarding calls.\n');

    onRequest<AgentBoardingCall, ModelVisa?>((req) async {
      final passport = req.event.passport;
      print(
        '  [Visa Office] Reviewing passport: '
        '${passport.modelFamily}/${passport.modelId}',
      );

      if (!supportedFamilies.contains(passport.modelFamily)) {
        print('  [Visa Office] Not our family. Conceding.\n');
        return null;
      }

      print('  [Visa Office] Match! Notarizing visa...');
      final client = createClient(passport);
      final visa = ModelVisa(
        passport: passport,
        provider: client.providerName,
        client: client,
      );
      print('  [Visa Office] Visa issued: $visa\n');
      return visa;
    }, priority: 0);
  }

  @override
  Future<void> detach() async {
    print('  [Visa Office] Office closed. All visas finalized.');
  }
}

class VerboseAnthropicPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('verbose_anthropic');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<VisaOffice>(
      const ServiceId('visa_office'),
      VerboseVisaOffice(),
      priority: 100,
    );
  }
}

Future<void> main() async {
  print('--- Setting up runtime ---\n');

  final runtime = PluginRuntime(plugins: [VerboseAnthropicPlugin()])..init();
  final session = await runtime.createSession();

  // Passport 1: a family the office supports.
  final anthropicPassport = ModelPassport(
    modelFamily: 'anthropic',
    modelId: 'claude-sonnet-4-5-20250929',
  );

  print('Presenting passport: $anthropicPassport');
  final anthropicVisa = await session.request<AgentBoardingCall, ModelVisa?>(
    AgentBoardingCall(anthropicPassport),
  );
  print('Result: $anthropicVisa\n');

  // Passport 2: an unrecognised family. maybeRequest returns null instead
  // of throwing when every handler concedes.
  final unknownPassport = ModelPassport(
    modelFamily: 'openai',
    modelId: 'gpt-4o',
  );

  print('Presenting passport: $unknownPassport');
  final unknownVisa = await session.maybeRequest<AgentBoardingCall, ModelVisa?>(
    AgentBoardingCall(unknownPassport),
  );
  print(
    'Result: ${unknownVisa ?? 'No visa issued. No office claimed this passport.'}\n',
  );

  await runtime.dispose();
}
