import 'package:model_embassy/src/credentials.dart';

/// The request event: an agent presents its passport and asks for a visa.
class AgentBoardingCall {
  final ModelPassport passport;
  const AgentBoardingCall(this.passport);
}

/// Emitted before the boarding call to allow routers to inspect/mutate
/// the passport based on the prompt or other context.
class PrepareResponseEvent {
  ModelPassport passport;
  final String prompt;
  PrepareResponseEvent({required this.passport, required this.prompt});
}
