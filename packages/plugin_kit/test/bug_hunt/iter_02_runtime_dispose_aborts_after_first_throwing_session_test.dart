@Skip('ISSUE-runtime-dispose-aborts-after-first-throwing-session: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')
library;

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ThrowingSessionPlugin extends SessionPlugin {
  _ThrowingSessionPlugin(this.onDetach);

  final void Function() onDetach;

  @override
  final PluginId pluginId = const PluginId('throwing_session');

  @override
  Future<void> detach(SessionPluginContext context) async {
    onDetach();
    throw StateError('detach failed');
  }
}

void main() {
  group('bug-hunt iter 2: runtime-dispose-aborts-after-first-throwing-session', () {
    test('disposes all sessions even when one session detach fails', () async {
      var detachCalls = 0;
      final plugin = _ThrowingSessionPlugin(() => detachCalls++);
      final runtime = PluginRuntime(plugins: [plugin]);

      runtime.init();
      await runtime.createSession();
      await runtime.createSession();

      await expectLater(
        runtime.dispose(),
        throwsA(isA<PluginLifecycleException>()),
      );
      expect(detachCalls, 2);
      expect(runtime.sessions, isEmpty);
    });
  });
}
