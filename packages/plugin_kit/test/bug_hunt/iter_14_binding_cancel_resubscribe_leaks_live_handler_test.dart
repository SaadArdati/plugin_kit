import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

const _pluginId = PluginId('bug_hunt.leak');
const _serviceId = ServiceId('leaky');

class _Evt {
  const _Evt();
}

class _LeakyService extends SessionStatefulPluginService {
  bool fired = false;

  @override
  void attach() {
    activeBindings.add(() {
      on<_Evt>((_) => fired = true);
    });
  }
}

class _LeakPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => _pluginId;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_LeakyService>(_serviceId, _LeakyService.new);
  }
}

void main() {
  group('bug-hunt iter 14: binding-cancel-resubscribe-leaks-live-handler', () {
    test(
      'disabling a stateful service fully detaches it from later session events',
      () async {
        final runtime = PluginRuntime(plugins: [_LeakPlugin()])..init();
        addTearDown(runtime.dispose);
        final session = await runtime.createSession();
        final service = session.resolve<_LeakyService>(_serviceId);

        await runtime.updateSessionSettings(
          session,
          newSettings: RuntimeSettings(
            services: {
              Pin(_pluginId, [_serviceId]): const ServiceSettings(
                enabled: false,
              ),
            },
          ),
        );

        await session.emit(const _Evt());
        expect(service.fired, isFalse);
      },
    );
  });
}
