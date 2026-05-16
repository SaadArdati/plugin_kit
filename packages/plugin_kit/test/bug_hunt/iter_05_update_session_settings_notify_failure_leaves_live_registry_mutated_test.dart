import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

const _pluginId = PluginId('notify_thrower');
const _serviceId = ServiceId('notify_thrower.service');

class _PhaseService extends PluginService {
  String get phase => config.getString('phase') ?? 'unset';
}

class _ThrowingNotifyPlugin extends SessionPlugin {
  bool throwOnNotify = false;
  @override
  PluginId get pluginId => _pluginId;
  @override
  void register(ScopedServiceRegistry registry) =>
      registry.registerSingleton<_PhaseService>(_serviceId, _PhaseService.new);
  @override
  Future<void> onPluginSettingsChanged(
    SessionPluginContext oldContext,
    SessionPluginContext newContext,
  ) async {
    if (throwOnNotify) throw StateError('notify failed');
  }
}

void main() {
  group(
    'bug-hunt iter 5: update-session-settings-notify-failure-leaves-live-registry-mutated',
    () {
      test(
        'restores prior service overrides when updateSessionSettings notify hook throws',
        () async {
          final plugin = _ThrowingNotifyPlugin();
          final runtime =
              PluginRuntime<GlobalPluginContext, SessionPluginContext>(
                plugins: [plugin],
              )..init();
          addTearDown(runtime.dispose);
          final oldSettings = RuntimeSettings(
            services: {
              Pin(_pluginId, [_serviceId]): const ServiceSettings(
                config: {'phase': 'old'},
              ),
            },
          );
          final session = await runtime.createSession(settings: oldSettings);
          expect(session.resolve<_PhaseService>(_serviceId).phase, 'old');
          plugin.throwOnNotify = true;
          await expectLater(
            runtime.updateSessionSettings(
              session,
              newSettings: RuntimeSettings(
                services: {
                  Pin(_pluginId, [_serviceId]): const ServiceSettings(
                    config: {'phase': 'new'},
                  ),
                },
              ),
            ),
            throwsA(isA<StateError>()),
          );
          expect(session.resolve<_PhaseService>(_serviceId).phase, 'old');
        },
      );
    },
  );
}
