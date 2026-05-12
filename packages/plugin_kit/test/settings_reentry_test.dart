// Verifies that concurrent `updateSettings` calls fail fast rather than
// silently interleaving reconciliation.
//
// `updateSettings` (and its sibling `updateGlobalSettings` /
// `updateSessionSettings`) walks plugin lifecycle and mutates registry
// state across `await` points. Two callers firing without external
// serialization would interleave these mutations and corrupt the
// `_enabledGlobalPluginIds` / registry / `_sessions` state.
//
// The docs (`troubleshooting.mdx`: "Two back-to-back plugin toggles
// silently lose the second one") document caller-managed serialization
// as the contract. The guard turns that documented contract into a loud
// runtime check.
//
// Sync re-entry from a `settingsStream` listener is NOT what this
// guards: by the time the controller's `.add()` fires (the last line
// of `updateSettings`), the outer reconciliation has already
// completed, so a listener kicking off `updateSettings(other)` is
// sequential, not concurrent.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _NoopGlobalPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('noop_global');
}

void main() {
  group('updateSettings re-entry guard', () {
    test(
      'a second updateSettings called while a prior one is in flight throws',
      () async {
        final runtime = PluginRuntime(plugins: [_NoopGlobalPlugin()])..init();

        // Kick off the first reconciliation; do NOT await yet. The async
        // body suspends at its first `await updateGlobalSettings(...)`,
        // giving us a window where reconciliation is in flight.
        final first = runtime.updateSettings(
          const RuntimeSettings(
            plugins: {PluginId('noop_global'): PluginConfig(enabled: true)},
          ),
        );

        // The second call must surface a StateError once awaited. Without
        // a guard it would silently interleave with the first call,
        // racing on `_enabledGlobalPluginIds`, the registry, and the
        // session list.
        await expectLater(
          () => runtime.updateSettings(
            const RuntimeSettings(
              plugins: {PluginId('noop_global'): PluginConfig(enabled: false)},
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('already in progress'),
            ),
          ),
        );

        // The first call still completes normally.
        await first;
        expect(runtime.isPluginAttached(const PluginId('noop_global')), isTrue);

        await runtime.dispose();
      },
    );

    test(
      'sequential updateSettings calls (awaited) do not trip the guard',
      () async {
        final runtime = PluginRuntime(plugins: [_NoopGlobalPlugin()])..init();

        // Standard usage: await each call. The guard must not fire here.
        await runtime.updateSettings(
          const RuntimeSettings(
            plugins: {PluginId('noop_global'): PluginConfig(enabled: true)},
          ),
        );
        await runtime.updateSettings(
          const RuntimeSettings(
            plugins: {PluginId('noop_global'): PluginConfig(enabled: false)},
          ),
        );

        expect(runtime.isPluginAttached(const PluginId('noop_global')), isFalse);

        await runtime.dispose();
      },
    );

    test(
      'updateSettings releases the guard when reconciliation throws',
      () async {
        // If a reconcile throws (e.g. a plugin raises during attach), the
        // guard must clear so subsequent updateSettings calls are not
        // permanently locked out. Start with the throwing plugin disabled
        // so init() does not blow up; the toggle-on call is what raises.
        final runtime = PluginRuntime(plugins: [_ThrowingOnEnablePlugin()])
          ..init(defaultEnabledPluginIds: const {});

        try {
          await runtime.updateSettings(
            const RuntimeSettings(
              plugins: {
                PluginId('throw_on_enable'): PluginConfig(enabled: true),
              },
            ),
          );
          fail('expected PluginLifecycleException');
        } on PluginLifecycleException {
          // expected: the plugin throws during attach
        }

        // A follow-up call must succeed (guard released).
        await runtime.updateSettings(
          const RuntimeSettings(
            plugins: {
              PluginId('throw_on_enable'): PluginConfig(enabled: false),
            },
          ),
        );

        await runtime.dispose();
      },
    );
  });
}

class _ThrowingOnEnablePlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('throw_on_enable');

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('attach boom');
  }
}
