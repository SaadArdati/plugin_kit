@Skip('ISSUE-20260515-1438-runtime-reinit-after-dispose-crashes: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')
library;

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter 6: runtime-reinit-after-dispose-crashes', () {
    test('allows init to run again after dispose', () async {
      final runtime = PluginRuntime();
      addTearDown(() async => runtime.dispose());

      runtime.init();
      await runtime.dispose();

      expect(() => runtime.init(), returnsNormally);
    });
  });
}
