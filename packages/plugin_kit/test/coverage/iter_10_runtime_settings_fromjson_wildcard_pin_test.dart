import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'RuntimeSettings.fromJson deserializes wildcard service keys as wildcard Pin entries',
    () {
      final json = <String, dynamic>{
        'services': {
          '*:agent.model': {
            'enabled': false,
            'config': {'provider': 'openai', 'model': 'gpt-4.1-mini'},
            'priority': 77,
          },
        },
      };

      final settings = RuntimeSettings.fromJson(json);
      final wildcardPin = Pin.wildcard(['agent', 'model']);

      expect(settings.services[wildcardPin], const ServiceSettings(
        enabled: false,
        config: {'provider': 'openai', 'model': 'gpt-4.1-mini'},
        priority: 77,
      ));
      expect(settings.services.keys.single.isWildcard, isTrue);
    },
  );
}
