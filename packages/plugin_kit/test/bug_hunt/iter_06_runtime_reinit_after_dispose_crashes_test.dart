import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter 6: runtime-reinit-after-dispose-crashes', () {
    test('rejects init() on a disposed runtime with StateError', () async {
      final runtime = PluginRuntime();
      runtime.init();
      await runtime.dispose();

      // Disposed runtimes are terminal by design. Reinit is rejected
      // explicitly rather than crashing with LateInitializationError.
      // Callers needing a fresh runtime construct a new instance.
      expect(() => runtime.init(), throwsA(isA<StateError>()));
    });
  });
}
