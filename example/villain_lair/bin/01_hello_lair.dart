/// # 01: Hello, Lair!
///
/// The smallest possible plugin: one service, one session, one greeting.
///
/// Covers:
/// - Defining a `SessionPlugin`
/// - Registering a service in the DI registry
/// - Initializing the runtime and creating a session
/// - Resolving a service from the session context
library;

import 'package:plugin_kit/plugin_kit.dart';

class EvilGreetingService {
  String greet(String name) =>
      'Welcome to VILLAIN, $name. '
      'Your complimentary evil laugh will be issued at orientation.';
}

/// Simplest plugin shape: registers one service, no attach logic.
class WelcomeDeskPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('welcome_desk');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<EvilGreetingService>(
      const ServiceId('greeting_service'),
      EvilGreetingService(),
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [WelcomeDeskPlugin()])..init();
  final session = await runtime.createSession();

  final greeter = session.context.resolve<EvilGreetingService>(
    ServiceId('greeting_service'),
  );

  print(greeter.greet('Gary'));
  // => Welcome to VILLAIN, Gary. Your complimentary evil laugh will be
  //    issued at orientation.

  print(greeter.greet('Dr. Nefarious'));
  // => Welcome to VILLAIN, Dr. Nefarious. Your complimentary evil laugh
  //    will be issued at orientation.

  await runtime.dispose();

  print('\nLair shut down. Gary forgot to lock the front door.');
}
