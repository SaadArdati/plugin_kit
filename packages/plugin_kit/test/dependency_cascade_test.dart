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
      final runtime = PluginRuntime();

      runtime.addPlugins([pluginA, pluginB]);
      runtime.init(settings: RuntimeSettings.empty());

      await runtime.updateSettings(
        RuntimeSettings(plugins: {PluginId('b'): PluginConfig(enabled: false)}),
      );

      final session = await runtime.createSession();

      // Runtime-effective state: plugin A is cascade-disabled due to missing dep.
      expect(session.isPluginEnabled(const PluginId('a')), isFalse);
      expect(pluginA.lifecycleCalls, isEmpty);

      // Settings-intent state: runtime getters still use base enablement.
      expect(runtime.enabledPluginIds, contains(const PluginId('a')));
      expect(
        runtime.enabledPlugins.map((plugin) => plugin.pluginId),
        contains(const PluginId('a')),
      );
      expect(runtime.isPluginEnabled(const PluginId('a')), isTrue);
      expect(
        runtime.isPluginEnabled(const PluginId('a'), runtime.settings),
        isTrue,
      );
      expect(runtime.attachedPluginIds, isNot(contains(const PluginId('a'))));
      expect(runtime.isPluginAttached(const PluginId('a')), isFalse);
      await runtime.dispose();
    },
  );
}
