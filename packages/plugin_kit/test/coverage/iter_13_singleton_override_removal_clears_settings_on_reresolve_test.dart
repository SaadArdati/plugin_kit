import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _SettingsCaptureService extends PluginService {
  final List<Map<String, dynamic>> injections = [];

  @override
  void onSettingsInjected() {
    injections.add({...settings});
  }
}

void main() {
  test(
    'updateSettings clears singleton injected settings when a matching override is removed',
    () {
      const pluginId = PluginId('alpha');
      const serviceId = ServiceId('svc');
      final registry = ServiceRegistry(
        overrides: [
          const LocalPluginOverride(
            plugin: pluginId,
            serviceId: serviceId,
            settings: {'mode': 'fast'},
          ),
        ],
      );
      registry.registerSingleton<_SettingsCaptureService>(
        pluginId: pluginId,
        serviceId: serviceId,
        create: _SettingsCaptureService.new,
      );

      final first = registry.resolve<_SettingsCaptureService>(serviceId);
      expect(first.injections.single, equals({'mode': 'fast'}));

      registry.updateSettings(overrides: const []);

      final second = registry.resolve<_SettingsCaptureService>(serviceId);
      expect(second, same(first));
      expect(second.injections.last, isEmpty);
    },
  );
}
