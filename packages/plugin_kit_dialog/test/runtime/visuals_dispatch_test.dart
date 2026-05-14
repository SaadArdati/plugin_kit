import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/plugins/plugins_tab_plugin.dart';

class _Plain extends GlobalPlugin {
  _Plain(String id, {this.flags = const []}) : pluginId = PluginId(id);

  @override
  final PluginId pluginId;
  final List<FeatureFlag> flags;
  @override
  List<FeatureFlag> get featureFlags => flags;

  @override
  void register(ScopedServiceRegistry registry) {}
}

/// Flutter plugin that self-registers its own row + service visuals.
class _SelfDecorating extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('self_decorating');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PluginKitVisual>(
      PluginKitVisualsPlugin.pluginVisualNamespace(pluginId),
      () => const PluginKitVisual(
        label: 'Self-Decorating Plugin',
        icon: Icon(Icons.palette),
        color: Color(0xFFAA00AA),
      ),
    );
    registry.registerSingleton<PluginKitVisual>(
      PluginKitVisualsPlugin.serviceVisualNamespace('tool.editor'),
      () => const PluginKitVisual(
        icon: Icon(Icons.edit),
        color: Color(0xFF00FF00),
      ),
    );
  }
}

void main() {
  group('PluginRuntime.isPluginEnabledByDefault', () {
    test('locked plugins are always on', () {
      expect(
        PluginRuntime.isPluginEnabledByDefault(
          _Plain('x', flags: const [FeatureFlag.locked]),
        ),
        isTrue,
      );
    });
    test('experimental plugins default off', () {
      expect(
        PluginRuntime.isPluginEnabledByDefault(
          _Plain('x', flags: const [FeatureFlag.experimental]),
        ),
        isFalse,
      );
    });
    test('plain plugins default on', () {
      expect(PluginRuntime.isPluginEnabledByDefault(_Plain('x')), isTrue);
    });
  });

  group('PluginKitVisual registry resolution', () {
    test('reads self-attached visuals when present', () {
      final runtime = PluginRuntime()
        ..addPlugin(_SelfDecorating())
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final visuals = runtime.globalRegistry.maybeResolve<PluginKitVisual>(
        PluginKitVisualsPlugin.visualOfService(const ServiceId('tool.editor')),
      );
      expect((visuals?.icon as Icon).icon, Icons.edit);
      expect(visuals?.color, const Color(0xFF00FF00));
    });

    test('host overlay wins against self-attached', () {
      final runtime = PluginRuntime()
        ..addPlugin(_SelfDecorating())
        ..addPlugin(
          PluginKitVisualsPlugin(
            serviceVisuals: const {
              ServiceId('tool.editor'): PluginKitVisual(
                icon: Icon(Icons.cancel),
                color: Color(0xFFFF00FF),
              ),
            },
          ),
        )
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final visuals = runtime.globalRegistry.maybeResolve<PluginKitVisual>(
        PluginKitVisualsPlugin.visualOfService(const ServiceId('tool.editor')),
      );
      expect((visuals?.icon as Icon).icon, Icons.cancel);
      expect(visuals?.color, const Color(0xFFFF00FF));
    });
  });

  group('PluginChipsBuilder', () {
    test('label falls back to raw pluginId when no override is registered', () {
      final runtime = PluginRuntime()
        ..addPlugin(_Plain('chat'))
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final rows = const PluginChipsBuilder()
          .build(runtime, RuntimeSettings())
          .all;
      expect(rows.single.label, 'chat');
      expect(rows.single.description, isNull);
      expect(rows.single.icon, isNull);
      expect(rows.single.color, isNull);
    });

    test('host overlay beats self-attached on the same key', () {
      final runtime = PluginRuntime()
        ..addPlugin(_SelfDecorating())
        ..addPlugin(
          PluginKitVisualsPlugin(
            pluginVisuals: const {
              PluginId('self_decorating'): PluginKitVisual(
                label: 'Adapter Override',
                icon: Icon(Icons.bolt),
              ),
            },
          ),
        )
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final row = const PluginChipsBuilder()
          .build(runtime, RuntimeSettings())
          .all
          .firstWhere((r) => r.pluginId == const PluginId('self_decorating'));
      expect(row.label, 'Adapter Override');
      expect((row.icon as Icon).icon, Icons.bolt);
    });

    test('override fields beat derived defaults', () {
      final runtime = PluginRuntime()
        ..addPlugin(_Plain('chat'))
        ..addPlugin(
          PluginKitVisualsPlugin(
            pluginVisuals: const {
              PluginId('chat'): PluginKitVisual(
                label: 'Chat',
                description: 'Override description.',
                icon: Icon(Icons.chat),
                color: Color(0xFF2196F3),
              ),
            },
          ),
        )
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final row = const PluginChipsBuilder()
          .build(runtime, RuntimeSettings())
          .all
          .firstWhere((r) => r.pluginId == const PluginId('chat'));
      expect(row.label, 'Chat');
      expect(row.description, 'Override description.');
      expect((row.icon as Icon).icon, Icons.chat);
      expect(row.color, const Color(0xFF2196F3));
    });

    test('isEnabled honors locked > settings override > defaultEnabled', () {
      final runtime = PluginRuntime(
        plugins: [
          _Plain('locked_one', flags: const [FeatureFlag.locked]),
          _Plain('plain_default'),
          _Plain('plain_overridden_off'),
          _Plain('beta_overridden_on', flags: const [FeatureFlag.experimental]),
          _Plain('beta_default_off', flags: const [FeatureFlag.experimental]),
        ],
      )..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      const settings = RuntimeSettings(
        plugins: {
          // Should be ignored: locked wins.
          PluginId('locked_one'): PluginConfig(enabled: false),
          PluginId('plain_overridden_off'): PluginConfig(enabled: false),
          PluginId('beta_overridden_on'): PluginConfig(enabled: true),
        },
      );

      final byId = {
        for (final chip
            in const PluginChipsBuilder().build(runtime, settings).all)
          chip.pluginId: chip,
      };

      expect(byId[const PluginId('locked_one')]!.isEnabled, isTrue);
      expect(byId[const PluginId('plain_default')]!.isEnabled, isTrue);
      expect(byId[const PluginId('plain_overridden_off')]!.isEnabled, isFalse);
      expect(byId[const PluginId('beta_overridden_on')]!.isEnabled, isTrue);
      expect(byId[const PluginId('beta_default_off')]!.isEnabled, isFalse);
    });
  });

  group('PluginChipsBuilder.build (groups)', () {
    test('partitions by experimental and counts enabled per partition', () {
      final runtime = PluginRuntime(
        plugins: [
          _Plain('locked_one', flags: const [FeatureFlag.locked]),
          _Plain('stable_on'),
          _Plain('stable_off'),
          _Plain('beta_on', flags: const [FeatureFlag.experimental]),
          _Plain('beta_off', flags: const [FeatureFlag.experimental]),
        ],
      )..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      const settings = RuntimeSettings(
        plugins: {
          PluginId('stable_off'): PluginConfig(enabled: false),
          PluginId('beta_on'): PluginConfig(enabled: true),
        },
      );

      final groups = const PluginChipsBuilder().build(runtime, settings);

      expect(groups.all.map((c) => c.pluginId), [
        'locked_one',
        'stable_on',
        'stable_off',
        'beta_on',
        'beta_off',
      ]);
      expect(groups.stable.map((c) => c.pluginId), [
        'locked_one',
        'stable_on',
        'stable_off',
      ]);
      expect(groups.experimental.map((c) => c.pluginId), [
        'beta_on',
        'beta_off',
      ]);

      // locked_one (locked) + stable_on (default) + beta_on (override).
      expect(groups.enabledCount, 3);
      // locked_one + stable_on; stable_off overridden off.
      expect(groups.stableEnabledCount, 2);
      // beta_on overridden on; beta_off default off.
      expect(groups.experimentalEnabledCount, 1);
    });
  });

  group('PluginChipsBuilder registration', () {
    test('higher-priority host registration overrides the default', () {
      final runtime = PluginRuntime()
        ..addPlugin(_BuilderHost())
        ..addPlugin(_OverridingChipsBuilderPlugin())
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      final builder = runtime.globalRegistry.resolve<PluginChipsBuilder>(
        PluginsTabPlugin.chipsBuilderId,
      );

      final groups = builder.build(runtime, RuntimeSettings());
      // Override returns an empty groups regardless of runtime.plugins.
      expect(groups.all, isEmpty);
      expect(groups.stable, isEmpty);
      expect(groups.experimental, isEmpty);
    });
  });

  group('PluginKitVisualsPlugin three-axis registration', () {
    test('registers PluginKitVisual under all three namespaces', () {
      final runtime = PluginRuntime()
        ..addPlugin(_RegistersAgentModel())
        ..addPlugin(
          PluginKitVisualsPlugin(
            pluginVisuals: const {
              PluginId('chat'): PluginKitVisual(
                label: 'Chat',
                color: Color(0xFF2196F3),
              ),
            },
            namespaceVisuals: const {
              Namespace('agent'): PluginKitVisual(
                label: 'Main Agent',
                color: Color(0xFF7C5CFF),
              ),
            },
            serviceVisuals: const {
              ServiceId.namespaced(Namespace('agent'), 'model'):
                  PluginKitVisual(label: 'Model & Provider'),
            },
          ),
        )
        ..init(settings: RuntimeSettings());
      addTearDown(runtime.dispose);

      expect(
        runtime.globalRegistry
            .maybeResolve<PluginKitVisual>(
              PluginKitVisualsPlugin.visualFor(const PluginId('chat')),
            )
            ?.label,
        'Chat',
      );
      expect(
        runtime.globalRegistry
            .maybeResolve<PluginKitVisual>(
              PluginKitVisualsPlugin.visualOf(const Namespace('agent')),
            )
            ?.label,
        'Main Agent',
      );
      expect(
        runtime.globalRegistry
            .maybeResolve<PluginKitVisual>(
              PluginKitVisualsPlugin.visualOfService(
                const ServiceId('agent.model'),
              ),
            )
            ?.label,
        'Model & Provider',
      );
    });

    test(
      'does not throw on attach when a referenced plugin id is not registered',
      () {
        // Visuals for a plugin that is installed-but-disabled or simply
        // unknown should not break runtime init. Validation is warn-only.
        final runtime = PluginRuntime()
          ..addPlugin(
            PluginKitVisualsPlugin(
              pluginVisuals: const {
                PluginId('ghost_plugin'): PluginKitVisual(label: 'Ghost'),
              },
            ),
          );
        addTearDown(runtime.dispose);

        runtime.init(settings: RuntimeSettings());
        // Visual still registered for later use if the plugin shows up.
        expect(
          runtime.globalRegistry
              .maybeResolve<PluginKitVisual>(
                PluginKitVisualsPlugin.visualFor(
                  const PluginId('ghost_plugin'),
                ),
              )
              ?.label,
          'Ghost',
        );
      },
    );

    test(
      'does not throw on attach when a referenced service key is not registered',
      () {
        final runtime = PluginRuntime()
          ..addPlugin(_RegistersAgentModel())
          ..addPlugin(
            PluginKitVisualsPlugin(
              serviceVisuals: const {
                // Could be a typo, or could be a service from a disabled plugin.
                ServiceId.namespaced(Namespace('agent'), 'modle'):
                    PluginKitVisual(label: 'Typo or future'),
              },
            ),
          );
        addTearDown(runtime.dispose);

        runtime.init(settings: RuntimeSettings());
        // Visual is still registered (warn-only validation).
        expect(
          runtime.globalRegistry
              .maybeResolve<PluginKitVisual>(
                PluginKitVisualsPlugin.visualOfService(
                  const ServiceId('agent.modle'),
                ),
              )
              ?.label,
          'Typo or future',
        );
      },
    );

    test('namespace visual without registered services does not throw', () {
      final runtime = PluginRuntime()
        ..addPlugin(_RegistersAgentModel())
        ..addPlugin(
          PluginKitVisualsPlugin(
            namespaceVisuals: const {
              // 'agent' is registered, 'unused_ns' is not.
              Namespace('agent'): PluginKitVisual(label: 'Main Agent'),
              Namespace('unused_ns'): PluginKitVisual(label: 'Phantom'),
            },
          ),
        );
      addTearDown(runtime.dispose);

      // Must not throw; warn-only on miss.
      runtime.init(settings: RuntimeSettings());

      // The unused namespace visual is still registered (no harm done).
      expect(
        runtime.globalRegistry
            .maybeResolve<PluginKitVisual>(
              PluginKitVisualsPlugin.visualOf(const Namespace('unused_ns')),
            )
            ?.label,
        'Phantom',
      );
    });
  });
}

/// Simulates `PluginsTabPlugin`'s default registration in a unit test
/// without dragging in the dialog widget tree.
class _BuilderHost extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('builder_host');
  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PluginChipsBuilder>(
      PluginsTabPlugin.chipsBuilderId,
      () => PluginChipsBuilder(),
    );
  }
}

class _OverridingChipsBuilder implements PluginChipsBuilder {
  const _OverridingChipsBuilder();
  @override
  PluginChipGroups build(PluginRuntime runtime, RuntimeSettings settings) =>
      PluginChipGroups(all: const [], stable: const [], experimental: const []);
}

class _OverridingChipsBuilderPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('overriding_chips_builder');
  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PluginChipsBuilder>(
      PluginsTabPlugin.chipsBuilderId,
      () => const _OverridingChipsBuilder(),
      priority: Priority.elevated,
    );
  }
}

/// Test helper: registers a single `agent.model` service so service
/// existence checks in the validator have a target.
class _RegistersAgentModel extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('chat');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<Object>(
      const Namespace('agent')('model'),
      () => Object(),
    );
  }
}
