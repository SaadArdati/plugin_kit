import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

const _pluginId = PluginId('rollback_gap_plugin');
const _serviceId = ServiceId('stateful');

class _StatefulService extends StatefulPluginService {}

class _ThrowingNotifyPlugin extends SessionPlugin {
  bool throwOnNotify = false;

  @override
  PluginId get pluginId => _pluginId;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_StatefulService>(
      _serviceId,
      _StatefulService.new,
    );
  }

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
    'bug-hunt iter 12: update-session-settings-notify-rollback-skips-service-lifecycle',
    () {
      test(
        'keeps previously attached service attached when settings update rolls back',
        () async {
          final plugin = _ThrowingNotifyPlugin();
          final runtime = PluginRuntime(plugins: [plugin])..init();
          addTearDown(runtime.dispose);
          final session = await runtime.createSession();
          final service = session.resolve<_StatefulService>(_serviceId);
          expect(service.hasContext, isTrue);
          plugin.throwOnNotify = true;

          await expectLater(
            runtime.updateSessionSettings(
              session,
              newSettings: RuntimeSettings(
                services: {
                  Pin(_pluginId, [_serviceId]): const ServiceSettings(
                    enabled: false,
                  ),
                },
              ),
            ),
            throwsA(isA<StateError>()),
          );

          expect(service.hasContext, isTrue);
        },
      );
    },
  );
}
