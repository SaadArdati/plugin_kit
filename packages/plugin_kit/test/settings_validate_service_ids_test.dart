// Validates that `RuntimeSettings.services` pins must reference a
// service id the named plugin actually registered, after `register`
// has run on every enabled plugin for the scope being initialised.
//
// Symmetrical to `settings_validate_plugin_ids_test.dart` on the
// service-id half. Same [UnknownReferencePolicy] gates it: defaults
// to [UnknownReferencePolicy.throwError] so a renamed or removed
// service id surfaces loudly during development. Cached production
// settings that survived a service rename across app upgrades should
// opt into [UnknownReferencePolicy.logAndSkip] to degrade gracefully.
import 'package:logging/logging.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _ConfigService extends PluginService {}

class _AlphaPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ConfigService>(
      const ServiceId('agent.model'),
      () => _ConfigService(),
    );
  }
}

class _SessionService extends PluginService {}

class _SessionAlphaPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('alpha');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SessionService>(
      const ServiceId('chat.model'),
      () => _SessionService(),
    );
  }
}

void main() {
  group('RuntimeSettings.services pin service-id validation', () {
    test('init throws when a pin references a service id the plugin did not '
        'register, under the default policy', () {
      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          settings: RuntimeSettings(
            services: {
              // Plugin "alpha" only registers ServiceId("agent.model").
              Pin('alpha', ['agent', 'renamed_in_v2']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('alpha'), contains('renamed_in_v2')),
          ),
        ),
      );
    });

    test('init under logAndSkip does NOT throw and logs once at severe '
        'with the unknown service id', () {
      final logs = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(logs.add);
      addTearDown(sub.cancel);

      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.logAndSkip,
          settings: RuntimeSettings(
            services: {
              Pin('alpha', ['agent', 'renamed_in_v2']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        returnsNormally,
      );

      final severe = logs
          .where((r) => r.level >= Level.SEVERE)
          .where((r) => r.message.contains('renamed_in_v2'))
          .toList();
      expect(severe, hasLength(1));
      expect(severe.single.message, contains('init'));
    });

    test('init under ignore does not throw and does not log severe', () {
      final logs = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(logs.add);
      addTearDown(sub.cancel);

      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.ignore,
          settings: RuntimeSettings(
            services: {
              Pin('alpha', ['agent', 'renamed_in_v2']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        returnsNormally,
      );

      final severe = logs
          .where((r) => r.level >= Level.SEVERE)
          .where((r) => r.message.contains('renamed_in_v2'))
          .toList();
      expect(severe, isEmpty);
    });

    test('init under throwError accepts a pin that matches a registered '
        'service id (regression: validator must not over-throw)', () {
      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          settings: RuntimeSettings(
            services: {
              Pin('alpha', ['agent', 'model']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        returnsNormally,
      );
    });

    test('createSession throws under default policy when a session pin '
        'references an unregistered service id on the named plugin', () async {
      final runtime = PluginRuntime(plugins: [_SessionAlphaPlugin()])..init();

      await expectLater(
        () => runtime.createSession(
          settings: RuntimeSettings(
            services: {
              // SessionAlpha registers ServiceId("chat.model") only.
              Pin('alpha', ['chat', 'removed_in_v3']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('alpha'), contains('removed_in_v3')),
          ),
        ),
      );

      await runtime.dispose();
    });

    test('wildcard pins are NOT validated against service-id registration: '
        'they intentionally target whoever wins, even when no plugin '
        'registered that id yet', () {
      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      // No registered service matches "agent.unreleased", but the
      // wildcard pin shape is unscoped by design and survives.
      expect(
        () => runtime.init(
          settings: RuntimeSettings(
            services: {
              Pin.wildcard(['agent', 'unreleased']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        returnsNormally,
      );
    });

    test('pins whose plugin id is unknown are NOT re-flagged by the '
        'service-id validator under logAndSkip: the plugin-id pass '
        'already surfaced them, so we do not duplicate the report', () {
      final logs = <LogRecord>[];
      final sub = Logger.root.onRecord.listen(logs.add);
      addTearDown(sub.cancel);

      final runtime = PluginRuntime(plugins: [_AlphaPlugin()]);
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.logAndSkip,
          settings: RuntimeSettings(
            services: {
              Pin('ghost_plug', ['agent', 'model']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        returnsNormally,
      );

      // Exactly one severe message names ghost_plug (the plugin-id
      // pass). The service-id pass must not log a second time for
      // the same pin.
      final severe = logs
          .where((r) => r.level >= Level.SEVERE)
          .where((r) => r.message.contains('ghost_plug'))
          .toList();
      expect(severe, hasLength(1));
    });
  });
}
