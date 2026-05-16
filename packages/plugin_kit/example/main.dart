// Minimal end-to-end example of plugin_kit. Builds a runtime with two
// plugins, opens a session, resolves a service, and emits an event the
// other plugin handles. Run with `dart run`.
//
// See packages/plugin_kit/README.md and the docs at
// https://plugin-kit.saad-ardati.dev/ for the full guide.

import 'package:plugin_kit/plugin_kit.dart';

class Greeter {
  String greet(String name) => 'Hello, $name!';
}

class UserArrived {
  const UserArrived(this.name);
  final String name;
}

class GreeterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('greeter');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Greeter>(
      const ServiceId('greeter'),
      () => Greeter(),
    );
  }
}

class WelcomePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('welcome');

  @override
  void register(ScopedServiceRegistry registry) {}

  @override
  void attach(SessionPluginContext context) {
    on<UserArrived>(context, (envelope) async {
      final greeter = context.resolve<Greeter>(const ServiceId('greeter'));
      print('[welcome] ${greeter.greet(envelope.event.name)}');
    });
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [GreeterPlugin(), WelcomePlugin()],
  )..init();

  final session = await runtime.createSession();

  await session.emit(const UserArrived('Saad'));
  await session.emit(const UserArrived('Ada'));

  await runtime.dispose();
}
