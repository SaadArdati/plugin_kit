import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

const _pluginId = PluginId('reentry_session');

const _enabled = RuntimeSettings(
  plugins: {_pluginId: PluginConfig(enabled: true)},
);

class _ReentryNotifyPlugin extends SessionPlugin {
  PluginRuntime<GlobalPluginContext, SessionPluginContext>? runtime;
  PluginSession<SessionPluginContext>? session;
  bool _triggered = false;
  bool hookFired = false;

  @override
  PluginId get pluginId => _pluginId;

  @override
  Future<void> onPluginSettingsChanged(
    SessionPluginContext oldContext,
    SessionPluginContext newContext,
  ) async {
    if (_triggered) return;
    _triggered = true;
    hookFired = true;

    final runtime = this.runtime;
    final session = this.session;
    if (runtime == null || session == null) return;

    // Re-entry: while _reconciling is set (outer call is mid-flight),
    // call updateSessionSettings on the same runtime+session. The guard
    // at _enterReconcile must reject this with a StateError. The error
    // propagates up through the async chain and the outer call rethrows
    // it after running its rollback path. The test asserts on that
    // observable behavior, plus the post-condition that the guard is
    // released so subsequent calls succeed.
    await runtime.updateSessionSettings(session, newSettings: _enabled);
  }
}

void main() {
  test(
    'updateSessionSettings re-entry from notify hook throws and releases guard',
    () async {
      final plugin = _ReentryNotifyPlugin();
      final runtime = PluginRuntime<GlobalPluginContext, SessionPluginContext>(
        plugins: [plugin],
      )..init(settings: _enabled);
      addTearDown(runtime.dispose);

      final session = await runtime.createSession(settings: _enabled);
      plugin
        ..runtime = runtime
        ..session = session;

      // Outer call. Notify hook fires during reconcile, re-enters
      // updateSessionSettings, hits the _enterReconcile guard, throws.
      // The outer call rethrows after rolling back.
      await expectLater(
        runtime.updateSessionSettings(session, newSettings: _enabled),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('updateSessionSettings'),
              contains('already in progress'),
            ),
          ),
        ),
      );

      // The hook MUST have fired; without this the test could pass for
      // any unrelated reason (e.g. the outer call throwing pre-hook).
      expect(
        plugin.hookFired,
        isTrue,
        reason: 'sanity: notify hook must have driven the re-entry',
      );

      // Guard must be released after the throw + rollback. The plugin's
      // _triggered flag stays true, so the next call will not re-trigger
      // the hook recursively; this becomes a normal updateSessionSettings.
      await expectLater(
        runtime.updateSessionSettings(session, newSettings: _enabled),
        completes,
        reason: '_reconciling guard must release after the throw',
      );
    },
  );
}
