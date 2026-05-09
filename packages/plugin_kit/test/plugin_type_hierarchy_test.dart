import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

// --- Test plugin implementations ---

class TestGlobalPlugin extends GlobalPlugin {
  @override
  final PluginId pluginId;
  final List<String> lifecycleCalls = [];
  final bool _experimental;

  TestGlobalPlugin(String id, {bool experimental = false})
    : pluginId = PluginId(id),
      _experimental = experimental;

  @override
  List<FeatureFlag> get featureFlags =>
      _experimental ? const [.experimental] : const [];

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
    registry.registerSingleton<String>(
      ServiceId('${pluginId}_service'),
      'Instance from $pluginId',
      priority: 100,
    );
  }

  @override
  void attach(GlobalPluginContext context) {
    lifecycleCalls.add('attach');
  }

  @override
  Future<void> detach(GlobalPluginContext context) {
    lifecycleCalls.add('detach');
    return Future<void>.value();
  }

  void clearCalls() => lifecycleCalls.clear();
}

class TestSessionPlugin extends SessionPlugin {
  @override
  final PluginId pluginId;
  final List<String> lifecycleCalls = [];
  final bool _experimental;

  TestSessionPlugin(String id, {bool experimental = false})
    : pluginId = PluginId(id),
      _experimental = experimental;

  @override
  List<FeatureFlag> get featureFlags =>
      _experimental ? const [.experimental] : const [];

  @override
  void register(ScopedServiceRegistry registry) {
    lifecycleCalls.add('register');
    registry.registerSingleton<String>(
      ServiceId('${pluginId}_service'),
      'Instance from $pluginId',
      priority: 100,
    );
  }

  @override
  void attach(SessionPluginContext context) {
    lifecycleCalls.add('attach');
  }

  @override
  Future<void> detach(SessionPluginContext context) {
    lifecycleCalls.add('detach');
    return Future<void>.value();
  }

  void clearCalls() => lifecycleCalls.clear();
}

void main() {
  group('Plugin base class', () {
    test('GlobalPlugin is a Plugin', () {
      final plugin = TestGlobalPlugin('test');
      expect(plugin, isA<Plugin>());
      expect(plugin, isA<GlobalPlugin>());
      expect(plugin, isNot(isA<SessionPlugin>()));
    });

    test('SessionPlugin is a Plugin', () {
      final plugin = TestSessionPlugin('test');
      expect(plugin, isA<Plugin>());
      expect(plugin, isA<SessionPlugin>());
      expect(plugin, isNot(isA<GlobalPlugin>()));
    });

    test('plugins with same pluginId are equal', () {
      final a = TestGlobalPlugin('config');
      final b = TestGlobalPlugin('config');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('plugins with different pluginIds are not equal', () {
      final a = TestGlobalPlugin('config');
      final b = TestGlobalPlugin('logging');
      expect(a, isNot(equals(b)));
    });

    test(
      'GlobalPlugin and SessionPlugin with same id are NOT equal (different runtimeType)',
      () {
        final global = TestGlobalPlugin('same_id');
        final session = TestSessionPlugin('same_id');
        expect(global, isNot(equals(session)));
      },
    );

    test('experimental flag is read from featureFlags', () {
      final stable = TestGlobalPlugin('stable');
      final experimental = TestGlobalPlugin('exp', experimental: true);
      expect(stable.featureFlags.contains(FeatureFlag.experimental), isFalse);
      expect(
        experimental.featureFlags.contains(FeatureFlag.experimental),
        isTrue,
      );
    });

    test('dependencies defaults to empty set', () {
      final plugin = TestGlobalPlugin('test');
      expect(plugin.dependencies, isEmpty);
    });

    test('toString includes runtimeType and pluginId', () {
      final plugin = TestGlobalPlugin('config');
      expect(plugin.toString(), contains('TestGlobalPlugin'));
      expect(plugin.toString(), contains('config'));
    });
  });

  group('Plugin lifecycle methods', () {
    test('GlobalPlugin.register populates registry', () {
      final plugin = TestGlobalPlugin('config');
      final registry = ServiceRegistry.empty();
      plugin.register(registry.scopedFor(plugin.pluginId));
      expect(plugin.lifecycleCalls, ['register']);
      expect(
        registry.resolve<String>(const ServiceId('config_service')),
        'Instance from config',
      );
    });

    test('SessionPlugin.register populates registry', () {
      final plugin = TestSessionPlugin('chat');
      final registry = ServiceRegistry.empty();
      plugin.register(registry.scopedFor(plugin.pluginId));
      expect(plugin.lifecycleCalls, ['register']);
      expect(
        registry.resolve<String>(const ServiceId('chat_service')),
        'Instance from chat',
      );
    });

    test('GlobalPlugin.attach receives GlobalPluginContext', () {
      final plugin = TestGlobalPlugin('config');
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
      );
      plugin.attach(context);
      expect(plugin.lifecycleCalls, ['attach']);
    });

    test('SessionPlugin.attach receives SessionPluginContext', () {
      final plugin = TestSessionPlugin('chat');
      final globalBus = EventBus();
      final context = SessionPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        globalBus: globalBus,
      );
      plugin.attach(context);
      expect(plugin.lifecycleCalls, ['attach']);
    });

    test('GlobalPlugin.detach cleans up', () async {
      final plugin = TestGlobalPlugin('config');
      final context = GlobalPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
      );
      plugin.attach(context);
      plugin.clearCalls();
      await plugin.detach(context);
      expect(plugin.lifecycleCalls, ['detach']);
    });

    test('SessionPlugin.detach cleans up', () async {
      final plugin = TestSessionPlugin('chat');
      final context = SessionPluginContext(
        registry: ServiceRegistry.empty(),
        bus: EventBus(),
        globalBus: EventBus(),
      );
      plugin.attach(context);
      plugin.clearCalls();
      await plugin.detach(context);
      expect(plugin.lifecycleCalls, ['detach']);
    });
  });
}
