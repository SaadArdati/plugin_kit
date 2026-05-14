import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

// PluginService subclass that records every settings injection so tests
// can assert which settings landed on the resolved instance.
class _ConfigCaptureService extends PluginService {
  Map<String, dynamic>? capturedSettings;

  @override
  void onSettingsInjected() {
    capturedSettings = settings;
  }
}

// All tests register the same logical service id; a single service slot is
// enough surface to exercise the full wildcard pipeline.
const _agentModel = ServiceId('agent.model');

class _ConfigPlugin extends GlobalPlugin {
  _ConfigPlugin({required String id, this.priority = 50})
    : pluginId = PluginId(id);

  @override
  final PluginId pluginId;

  final int priority;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_ConfigCaptureService>(
      _agentModel,
      () => _ConfigCaptureService(),
      priority: priority,
    );
  }
}

void main() {
  late PluginRuntime runtime;

  setUp(() => runtime = PluginRuntime());
  tearDown(() async {
    try {
      await runtime.dispose();
    } on PluginLifecycleException {
      // Some tests leave plugins in unusual states; ignore detach errors.
    }
  });

  group('Wildcard override pipeline', () {
    test('wildcard config injects into the current winner', () {
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(
              config: {'temperature': 0.7},
            ),
          },
        ),
      );

      final service = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(service.capturedSettings, equals({'temperature': 0.7}));
      expect(service.pluginId, 'alpha'); // higher native priority wins
    });

    test('plugin-specific override beats wildcard for the same service', () {
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(
              config: {'source': 'wildcard'},
            ),
            Pin('alpha', ['agent', 'model']): ServiceSettings(
              config: {'source': 'specific'},
            ),
          },
        ),
      );

      final service = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(service.capturedSettings, equals({'source': 'specific'}));
    });

    test('single ServiceSettings carrying both priority and config injects '
        'both into the targeted plugin', () {
      // Regression: previously _appendServiceOverrides exploded one
      // ServiceSettings into separate priority and settings rows, and
      // _overrideForInjection's firstOrNull would return the priority row
      // (with empty settings), shadowing the config row within the SAME
      // ServiceSettings. Config was silently dropped.
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin('beta', ['agent', 'model']): ServiceSettings(
              priority: 200,
              config: {'temperature': 0.5},
            ),
          },
        ),
      );

      final wrapper = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
        _agentModel,
      );
      expect(wrapper.pluginId, 'beta', reason: 'priority bump made beta win');
      expect(wrapper.priority, 200);

      final service = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        _agentModel,
      );
      expect(
        service.capturedSettings,
        equals({'temperature': 0.5}),
        reason:
            'config from the same ServiceSettings must survive alongside '
            'the priority bump',
      );
    });

    test('priority-only plugin-specific lets wildcard config flow into the '
        'now-winning plugin', () {
      // Per-knob layering: the plugin-specific entry only sets priority,
      // so the wildcard's config falls through and reaches the new winner.
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(
              config: {'temperature': 0.5},
            ),
            Pin('beta', ['agent', 'model']): ServiceSettings(priority: 200),
          },
        ),
      );

      final wrapper = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
        _agentModel,
      );
      expect(wrapper.pluginId, 'beta');
      expect(wrapper.priority, 200);

      final service = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        _agentModel,
      );
      expect(
        service.capturedSettings,
        equals({'temperature': 0.5}),
        reason:
            'wildcard config layers under a priority-only plugin-specific '
            'override',
      );
    });

    test('wildcard disable AND-merges with plugin-specific priority bump', () {
      // Without AND-merge, a priority-only plugin-specific override would
      // accidentally shadow the wildcard's enabled:false and silently
      // re-enable the slot. AND-merge keeps the slot disabled.
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(enabled: false),
            Pin('beta', ['agent', 'model']): ServiceSettings(priority: 200),
          },
        ),
      );

      expect(
        () =>
            runtime.globalRegistry.resolve<_ConfigCaptureService>(_agentModel),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disabled by overrides'),
          ),
        ),
      );
    });

    test('plugin-specific override targeting unknown plugin throws StateError '
        'under throwError policy', () {
      runtime.addPlugin(_ConfigPlugin(id: 'alpha'));

      expect(
        () => runtime.init(
          unknownReferencePolicy: UnknownReferencePolicy.throwError,
          settings: RuntimeSettings(
            services: {
              Pin('unknown', ['agent', 'model']): ServiceSettings(
                config: {'k': 'v'},
              ),
            },
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('unknown plugin "unknown"'),
          ),
        ),
      );
    });

    test('wildcard for unregistered service is silently dropped', () {
      runtime.addPlugin(_ConfigPlugin(id: 'alpha'));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['nonexistent', 'service']): ServiceSettings(
              config: {'k': 'v'},
            ),
          },
        ),
      );

      // The lone real service is unaffected -- no injectSettings call was made
      // (no override matched), so capturedSettings remains null.
      final service = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(service.capturedSettings, isNull);

      // No override was materialized for the missing service.
      final missing = runtime.globalRegistry.overrides.where(
        (o) => o.serviceId == const ServiceId('nonexistent.service'),
      );
      expect(missing, isEmpty);
    });

    test('disabled wildcard disables the winning slot', () {
      runtime.addPlugin(_ConfigPlugin(id: 'alpha'));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(enabled: false),
          },
        ),
      );

      expect(
        () => runtime.globalRegistry.resolve<_ConfigCaptureService>(
          const ServiceId('agent.model'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disabled by overrides'),
          ),
        ),
      );
    });

    test('wildcard priority binds to the winner only, not its rivals', () {
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 50))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 100));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(priority: 200),
          },
        ),
      );

      final agentOverrides = runtime.globalRegistry.overrides
          .where((o) => o.serviceId == const ServiceId('agent.model'))
          .toList();
      final pluginIds = agentOverrides.map((o) => o.plugin).toSet();
      // Two entries: one for the winner (beta), one for the wildcard sentinel.
      // alpha's wrapper has no override targeting it.
      expect(
        pluginIds,
        equals({const PluginId('beta'), PluginId.winnerScoped}),
      );
    });

    test('wildcard priority shifts the just-registered winner live', () {
      // The wildcard pipeline forwards priority by creating a plugin-scoped
      // override targeting the current winner. updateSettings then restamps
      // any wrapper whose plugin-scoped override carries a non-null
      // priority, so beta's wrapper picks up the wildcard's 200 without
      // having to be re-registered.
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 50))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 100));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(priority: 200),
          },
        ),
      );

      final wrapper = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(wrapper.pluginId, 'beta');
      expect(wrapper.priority, 200, reason: 'effective priority is restamped');
      expect(wrapper.basePriority, 100, reason: 'registration value preserved');

      // The winner's plugin-scoped override entry still carries the 200,
      // which is what makes the restamp survive a later re-registration.
      final betaOverride = runtime.globalRegistry.overrides.firstWhere(
        (o) =>
            o.serviceId == const ServiceId('agent.model') &&
            o.plugin == const PluginId('beta'),
      );
      expect(betaOverride.priority, 200);
    });

    test('wildcard priority survives the winner re-registering', () {
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 50))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 100));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(priority: 200),
          },
        ),
      );

      // Simulate a re-registration (e.g., a model swap): beta calls
      // registerSingleton again with a different native priority. The
      // effective priority should still come from the wildcard's
      // forwarded override, not the new native value, so live behavior
      // stays consistent across re-registrations.
      runtime.globalRegistry
          .scopedFor(const PluginId('beta'))
          .registerSingleton<_ConfigCaptureService>(
            const ServiceId('agent.model'),
            () => _ConfigCaptureService(),
            priority: 75, // intended native priority
          );

      final wrapper = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(wrapper.pluginId, 'beta');
      expect(wrapper.priority, 200);
      expect(wrapper.basePriority, 75);
    });

    test('wildcard config persists when winner changes', () {
      // alpha wins at init. Wildcard config is captured. A late-registered
      // gamma with higher priority then wins. _overrideForInjection has no
      // plugin-specific entry for gamma, falls back to PluginId.winnerScoped, and
      // injects the wildcard's config into gamma's instance.
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

      runtime.init(
        settings: RuntimeSettings(
          services: {
            Pin.wildcard(['agent', 'model']): ServiceSettings(
              config: {'source': 'wildcard'},
            ),
          },
        ),
      );

      // Sanity: alpha currently wins and has the wildcard's config.
      final initial = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(initial.pluginId, 'alpha');
      expect(initial.capturedSettings, equals({'source': 'wildcard'}));

      // A new high-priority registration arrives outside the runtime's
      // wildcard-resolution flow (e.g., a third plugin registering late).
      runtime.globalRegistry
          .scopedFor(const PluginId('gamma'))
          .registerSingleton<_ConfigCaptureService>(
            const ServiceId('agent.model'),
            () => _ConfigCaptureService(),
            priority: 300,
          );

      final after = runtime.globalRegistry.resolve<_ConfigCaptureService>(
        const ServiceId('agent.model'),
      );
      expect(after.pluginId, 'gamma');
      // Config persists across the winner change via the PluginId.winnerScoped fallback.
      expect(after.capturedSettings, equals({'source': 'wildcard'}));
    });
  });

  group('Plugin-specific priority restamp', () {
    test(
      'updateSettings restamps an existing wrapper when a new plugin-specific priority lands',
      () async {
        // Regression: previously, changing ServiceSettings.priority for an
        // already-registered plugin updated the override list but left the
        // existing wrapper.priority at its registration-time value, so the
        // sort order (and therefore the live winner) did not change until
        // the plugin was re-registered (which only happens on session
        // re-create or detach/attach). updateSettings must restamp wrappers
        // in place.
        runtime
          ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
          ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

        runtime.init();

        // Sanity: alpha wins natively.
        var winner = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
          const ServiceId('agent.model'),
        );
        expect(winner.pluginId, const PluginId('alpha'));
        expect(winner.priority, 100);

        // Update settings: bump beta's priority above alpha's.
        await runtime.updateGlobalSettings(
          oldSettings: const RuntimeSettings(),
          newSettings: RuntimeSettings(
            services: {
              Pin('beta', ['agent', 'model']): ServiceSettings(priority: 200),
            },
          ),
        );

        // Beta now wins, live, with no re-registration.
        winner = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
          const ServiceId('agent.model'),
        );
        expect(winner.pluginId, const PluginId('beta'));
        expect(winner.priority, 200);
        expect(winner.basePriority, 50, reason: 'base priority is preserved');
      },
    );

    test(
      'updateSettings reverts a wrapper when the priority override is removed',
      () async {
        runtime
          ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
          ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));

        runtime.init(
          settings: RuntimeSettings(
            services: {
              Pin('beta', ['agent', 'model']): ServiceSettings(priority: 200),
            },
          ),
        );

        // beta wins at 200 thanks to the override.
        var winner = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
          const ServiceId('agent.model'),
        );
        expect(winner.pluginId, const PluginId('beta'));
        expect(winner.priority, 200);

        // Remove the priority override.
        await runtime.updateGlobalSettings(
          oldSettings: RuntimeSettings(
            services: {
              Pin('beta', ['agent', 'model']): ServiceSettings(priority: 200),
            },
          ),
          newSettings: const RuntimeSettings(),
        );

        // alpha (priority 100) wins again; beta is back at its base 50.
        winner = runtime.globalRegistry.resolveRaw<_ConfigCaptureService>(
          const ServiceId('agent.model'),
        );
        expect(winner.pluginId, const PluginId('alpha'));

        final betaWrapper = runtime.globalRegistry
            .getRegistrations(const ServiceId('agent.model'))!
            .firstWhere((w) => w.pluginId == const PluginId('beta'));
        expect(betaWrapper.priority, 50);
      },
    );

    test('ServiceRegistry.copy() snapshots wrapper priorities', () {
      // Regression A3: copy() previously shared wrapper instances with
      // the live registry, so a subsequent updateSettings call mutated
      // priority on the snapshot too. oldContext (used by
      // Plugin.onPluginSettingsChanged to compare pre- vs post-update
      // state) would observe post-update priorities and report no
      // change.
      runtime
        ..addPlugin(_ConfigPlugin(id: 'alpha', priority: 100))
        ..addPlugin(_ConfigPlugin(id: 'beta', priority: 50));
      runtime.init();

      // Snapshot the registry.
      final snapshot = runtime.globalRegistry.copy();

      // Mutate priorities on the live registry by applying overrides.
      runtime.globalRegistry.updateSettings(
        overrides: [
          LocalPluginOverride(
            plugin: const PluginId('beta'),
            serviceId: const ServiceId('agent.model'),
            priority: 999,
          ),
        ],
      );

      // Live registry sees the new priority.
      final liveBeta = runtime.globalRegistry
          .getRegistrations(const ServiceId('agent.model'))!
          .firstWhere((w) => w.pluginId == const PluginId('beta'));
      expect(liveBeta.priority, 999);

      // Snapshot must NOT see the mutation; it owns its own wrappers.
      final snapshotBeta = snapshot
          .getRegistrations(const ServiceId('agent.model'))!
          .firstWhere((w) => w.pluginId == const PluginId('beta'));
      expect(
        snapshotBeta.priority,
        50,
        reason: 'snapshot wrapper priority must remain pre-update',
      );
      expect(
        identical(liveBeta, snapshotBeta),
        isFalse,
        reason: 'snapshot must hold cloned wrapper instances',
      );
    });
  });
}
