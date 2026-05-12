// Validates that `RuntimeSettings.plugins` keys must reference plugin ids
// known to the runtime, symmetrically with `RuntimeSettings.services` pins.
//
// History: a typo in a `plugins:` key (e.g. `PluginId('alphaa')` instead
// of `PluginId('alpha')`) was originally silently ignored, while a typo
// in a `services:` pin DID throw. Validation closed that gap, then the
// policy enum [UnknownReferencePolicy] made the response configurable
// because cached settings from a prior app version legitimately reference
// renamed/removed ids and should not crash startup by default.
//
// This file pins both halves of the contract:
//   - default [UnknownReferencePolicy.throwError] throws everywhere
//     unknown ids are seen (init / createSession / updateSettings /
//     updateSessionSettings, on both plugins-map and services pin keys).
//   - opt-in [UnknownReferencePolicy.logAndSkip] does NOT throw; the
//     known entries still apply and a single severe log surfaces drift.
//   - [UnknownReferencePolicy.ignore] does not throw and does not log.
import 'package:logging/logging.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _AlphaPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');
}

void main() {
  group('RuntimeSettings.plugins key validation (throwError policy)', () {
    test(
      'init rejects plugins map entries that reference unknown plugin ids',
      () {
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);

        expect(
          () => runtime.init(
            unknownReferencePolicy: UnknownReferencePolicy.throwError,
            settings: const RuntimeSettings(
              plugins: {
                // typo: should be 'alpha'
                PluginId('alphaa'): PluginConfig(enabled: false),
              },
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('unknown plugin'), contains('alphaa')),
            ),
          ),
        );
      },
    );

    test('init accepts plugins map entries that match a registered plugin', () {
      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.throwError,
          settings: const RuntimeSettings(
            plugins: {PluginId('alpha'): PluginConfig(enabled: false)},
          ),
        ),
        returnsNormally,
      );
    });

    test(
      'updateSettings rejects plugins map entries with unknown plugin ids',
      () async {
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()])
          ..init(unknownReferencePolicy: UnknownReferencePolicy.throwError);

        await expectLater(
          () => runtime.updateSettings(
            const RuntimeSettings(
              plugins: {
                PluginId('not_a_real_plugin'): PluginConfig(enabled: true),
              },
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('not_a_real_plugin'),
            ),
          ),
        );

        await runtime.dispose();
      },
    );

    test(
      'createSession rejects plugins map entries with unknown plugin ids',
      () async {
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()])
          ..init(unknownReferencePolicy: UnknownReferencePolicy.throwError);

        await expectLater(
          () => runtime.createSession(
            settings: const RuntimeSettings(
              plugins: {PluginId('typo_id'): PluginConfig(enabled: true)},
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('typo_id'),
            ),
          ),
        );

        await runtime.dispose();
      },
    );

    test(
      'updateSessionSettings rejects plugins map entries with unknown plugin ids',
      () async {
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()])
          ..init(unknownReferencePolicy: UnknownReferencePolicy.throwError);
        final session = await runtime.createSession();

        await expectLater(
          () => runtime.updateSessionSettings(
            session,
            newSettings: const RuntimeSettings(
              plugins: {
                PluginId('does_not_exist'): PluginConfig(enabled: true),
              },
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('does_not_exist'),
            ),
          ),
        );

        await runtime.dispose();
      },
    );

    test(
      'services pin validation still rejects unknown plugin ids (regression)',
      () {
        // The pin-side validator is symmetric with the plugins-map one;
        // throwError must still throw on a pin's unknown plugin id.
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
        expect(
          () => runtime.init(
            unknownReferencePolicy: UnknownReferencePolicy.throwError,
            settings: RuntimeSettings(
              services: {
                Pin('not_registered_plugin', ['svc']): const ServiceSettings(
                  enabled: false,
                ),
              },
            ),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('RuntimeSettings.plugins key validation (logAndSkip policy)', () {
    test('init with logAndSkip does NOT throw on an unknown plugin id and '
        'logs once at severe with the unknown id', () {
      final logs = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(logs.add);
      addTearDown(sub.cancel);

      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.logAndSkip,
          settings: const RuntimeSettings(
            plugins: {
              // typo: should be 'alpha'
              PluginId('alphaa'): PluginConfig(enabled: false),
            },
          ),
        ),
        returnsNormally,
      );

      final severe = logs
          .where((r) => r.level >= Level.SEVERE)
          .where((r) => r.message.contains('alphaa'))
          .toList();
      expect(severe, hasLength(1));
      expect(severe.single.message, contains('init'));
    });

    test('updateSessionSettings with logAndSkip does NOT throw and still '
        'applies known overrides', () async {
      final runtime = PluginRuntime(plugins: [_AlphaPlugin()])
        ..init(unknownReferencePolicy: UnknownReferencePolicy.logAndSkip);
      final session = await runtime.createSession();

      await expectLater(
        () => runtime.updateSessionSettings(
          session,
          newSettings: const RuntimeSettings(
            plugins: {
              PluginId('alpha'): PluginConfig(enabled: false),
              // unknown id is silently dropped under logAndSkip; the
              // known 'alpha' override above must still take effect.
              PluginId('renamed_in_v2'): PluginConfig(enabled: true),
            },
          ),
        ),
        returnsNormally,
      );

      await runtime.dispose();
    });

    test(
      'default policy (no argument) throws on an unknown plugin id at init',
      () {
        final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
        expect(
          () => runtime.init(
            // No unknownReferencePolicy argument: default must be strict.
            settings: const RuntimeSettings(
              plugins: {PluginId('alphaa'): PluginConfig(enabled: false)},
            ),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('RuntimeSettings.plugins key validation (ignore policy)', () {
    test('init with ignore policy does not throw and does not log severe', () {
      final logs = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(logs.add);
      addTearDown(sub.cancel);

      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.ignore,
          settings: const RuntimeSettings(
            plugins: {PluginId('alphaa'): PluginConfig(enabled: false)},
          ),
        ),
        returnsNormally,
      );

      final severe = logs
          .where((r) => r.level >= Level.SEVERE)
          .where((r) => r.message.contains('alphaa'))
          .toList();
      expect(severe, isEmpty);
    });
  });
}
