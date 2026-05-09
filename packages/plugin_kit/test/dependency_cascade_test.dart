import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _PluginA extends SessionPlugin<SessionPluginContext> {
  @override
  PluginId get pluginId => const PluginId('a');

  @override
  Set<PluginId> get dependencies => {const PluginId('b')};

  final List<String> lifecycleCalls = [];

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
  }

  @override
  void attach(SessionPluginContext context) {
    lifecycleCalls.add('attach');
  }
}

class _PluginB extends SessionPlugin<SessionPluginContext> {
  @override
  PluginId get pluginId => const PluginId('b');

  final List<String> lifecycleCalls = [];

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
  }

  @override
  void attach(SessionPluginContext context) {
    lifecycleCalls.add('attach');
  }
}

void main() {
  test(
    'enabledPlugins reports settings-intent, not runtime-effective state',
    () async {
      final pluginA = _PluginA();
      final pluginB = _PluginB();
      final manager = PluginRuntimeManager();

      manager.addPlugins([pluginA, pluginB]);
      manager.init(initialSettings: RuntimeSettings.empty());

      await manager.updateSettings(
        RuntimeSettings(plugins: {PluginId('b'): PluginConfig(enabled: false)}),
      );

      final session = await manager.createSession();

      // Runtime-effective state: plugin A is cascade-disabled due to missing dep.
      expect(session.isPluginEnabled(const PluginId('a')), isFalse);
      expect(pluginA.lifecycleCalls, isEmpty);

      // Settings-intent state: manager getters still use base enablement.
      expect(manager.enabledPluginIds, contains(const PluginId('a')));
      expect(
        manager.enabledPlugins.map((plugin) => plugin.pluginId),
        contains(const PluginId('a')),
      );
      expect(manager.isPluginEnabled(const PluginId('a')), isTrue);
      expect(
        manager.runtime.isPluginEnabled(const PluginId('a'), manager.settings),
        isTrue,
      );
      expect(manager.attachedPluginIds, isNot(contains(const PluginId('a'))));
      expect(manager.isPluginAttached(const PluginId('a')), isFalse);
      await manager.dispose();
    },
  );
}
