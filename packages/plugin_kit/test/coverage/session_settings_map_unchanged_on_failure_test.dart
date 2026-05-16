import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

const _pluginId = PluginId('throwing_notify');
const _serviceId = ServiceId('throwing_notify.service');

class _ThrowingNotifyPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => _pluginId;

  bool armed = false;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(_serviceId, () => Object());
  }

  @override
  Future<void> onPluginSettingsChanged(
    SessionPluginContext oldContext,
    SessionPluginContext newContext,
  ) async {
    if (armed) {
      armed = false;
      throw StateError('induced notify failure for test');
    }
  }
}

void main() {
  test(
    '_sessionSettings unchanged when updateSessionSettings notify hook throws',
    () async {
      final plugin = _ThrowingNotifyPlugin();
      final runtime = PluginRuntime<GlobalPluginContext, SessionPluginContext>(
        plugins: [plugin],
      )..init();
      addTearDown(runtime.dispose);

      final session = await runtime.createSession();

      final initial = RuntimeSettings(
        plugins: {_pluginId: const PluginConfig(enabled: true)},
      );
      await runtime.updateSessionSettings(session, newSettings: initial);

      final before = Map.of(runtime.debugSessionSettings);
      expect(before[session], initial, reason: 'sanity: starting state pinned');

      plugin.armed = true;

      final next = RuntimeSettings(
        plugins: {_pluginId: const PluginConfig(enabled: true)},
        services: {
          Pin(_pluginId, [_serviceId]): const ServiceSettings(
            config: {'phase': 'next'},
          ),
        },
      );

      await expectLater(
        runtime.updateSessionSettings(session, newSettings: next),
        throwsA(isA<StateError>()),
      );

      expect(runtime.debugSessionSettings, before);
      expect(
        runtime.debugSessionSettings[session],
        initial,
        reason: 'failed update must NOT have applied next settings',
      );
    },
  );
}
