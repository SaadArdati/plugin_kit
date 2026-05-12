// Verifies that cross-scope service pins are NOT silently dropped: they
// are partitioned per phase (global pins applied at init, session pins
// applied at createSession). A misspelled plugin id throws via
// `_validateServiceSettingPluginIds` (services side) and
// `_validatePluginConfigPluginIds` (plugins side).
//
// This is the verification half of the "cross-scope drop" review item:
// the only "drop" the partition performs is intentional (skip the other
// scope), and unknown ids fail loudly thanks to validation, so a typo
// cannot quietly disappear.
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _GlobalConfigService extends PluginService {}

class _SessionConfigService extends PluginService {}

class _GlobalScopePlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('global_plug');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_GlobalConfigService>(
      const ServiceId('svc'),
      () => _GlobalConfigService(),
    );
  }
}

class _SessionScopePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('session_plug');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SessionConfigService>(
      const ServiceId('svc'),
      () => _SessionConfigService(),
    );
  }
}

void main() {
  group('cross-scope service pin handling', () {
    test('a global plugin pin in settings is applied at init and ignored at '
        'createSession (no silent loss of intent)', () async {
      final runtime = PluginRuntime(
        plugins: [_GlobalScopePlugin(), _SessionScopePlugin()],
      );
      final settings = RuntimeSettings(
        services: {
          // Override config on the GLOBAL plugin's service.
          Pin('global_plug', ['svc']): const ServiceSettings(
            config: {'global_key': 'global_value'},
          ),
          // Override config on the SESSION plugin's service.
          Pin('session_plug', ['svc']): const ServiceSettings(
            config: {'session_key': 'session_value'},
          ),
        },
      );

      runtime.init(settings: settings);

      // Global side: init's partition picked up the global pin and
      // attached it to the global registry's override list.
      final globalOverrides = runtime.globalRegistry.overrides
          .where((o) => o.plugin == const PluginId('global_plug'))
          .toList();
      expect(
        globalOverrides,
        isNotEmpty,
        reason: 'global pin must be applied at init',
      );

      // Session side: same settings passed to createSession, the
      // session partition picks up the session pin and attaches it to
      // the session's override list.
      final session = await runtime.createSession(settings: settings);
      final sessionOverrides = session.registry.overrides
          .where((o) => o.plugin == const PluginId('session_plug'))
          .toList();
      expect(
        sessionOverrides,
        isNotEmpty,
        reason: 'session pin must be applied at createSession',
      );

      // Same settings, processed by both phases without loss.
      await runtime.dispose();
    });

    test('a misspelled plugin id in a service pin throws at init '
        '(no silent drop) under throwError policy', () {
      final runtime = PluginRuntime(
        plugins: [_GlobalScopePlugin(), _SessionScopePlugin()],
      );
      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.throwError,
          settings: RuntimeSettings(
            services: {
              // Typo: 'globl_plug' instead of 'global_plug'.
              Pin('globl_plug', ['svc']): const ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('globl_plug'),
          ),
        ),
      );
    });

    test('a wildcard service pin survives both init and createSession '
        'partitions (matches whatever winner exists in each scope)', () async {
      final runtime = PluginRuntime(
        plugins: [_GlobalScopePlugin(), _SessionScopePlugin()],
      );
      final settings = RuntimeSettings(
        services: {
          Pin.wildcard(['svc']): const ServiceSettings(
            config: {'shared': 'wildcard_value'},
          ),
        },
      );

      runtime.init(settings: settings);

      // Wildcard resolved to the global winner at init; the global's
      // wrapper has the wildcard's config injected via the
      // winnerScoped fallback.
      final globalService = runtime.globalRegistry
          .resolve<_GlobalConfigService>(const ServiceId('svc'));
      expect(globalService.config.getString('shared'), 'wildcard_value');

      final session = await runtime.createSession(settings: settings);
      final sessionService = session.registry.resolve<_SessionConfigService>(
        const ServiceId('svc'),
      );
      expect(
        sessionService.config.getString('shared'),
        'wildcard_value',
        reason: 'wildcard pin must reach the session winner too',
      );

      await runtime.dispose();
    });
  });
}
