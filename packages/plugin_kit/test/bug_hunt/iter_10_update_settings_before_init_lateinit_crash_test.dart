import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter 10: update-settings-before-init-lateinit-crash', () {
    test('throws StateError when updateSettings is called before init', () async {
      final runtime = PluginRuntime();

      await expectLater(
        runtime.updateSettings(const RuntimeSettings()),
        throwsA(isA<StateError>()),
      );
    });
  });
}
