import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  test(
    'copyWith keeps existing priority when null priority is passed while applying enabled change',
    () {
      const original = ServiceSettings(enabled: true, priority: 42);

      final updated = original.copyWith(enabled: false, priority: null);

      expect(updated.enabled, isFalse);
      expect(updated.priority, 42);
    },
  );
}
