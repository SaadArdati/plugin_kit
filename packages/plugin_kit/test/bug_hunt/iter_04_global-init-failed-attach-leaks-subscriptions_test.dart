@Skip('ISSUE-20260515-1438-global-init-failed-attach-leaks-subscriptions: failing reproducer kept as evidence; see PACKAGE_ISSUES.md')
library;

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _MarkerEvent {
  const _MarkerEvent();
}

int _markerHits = 0;

class _LeakyStatefulService extends StatefulPluginService {
  @override
  void attach() {
    on<_MarkerEvent>((_) {
      _markerHits += 1;
    });
  }
}

class _GlobalAttachThrowsPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('global_attach_throws');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_LeakyStatefulService>(
      const ServiceId('leaky_service'),
      () => _LeakyStatefulService(),
    );
  }

  @override
  void attach(GlobalPluginContext context) {
    throw StateError('boom');
  }
}

void main() {
  group('bug-hunt iter 4: global-init-failed-attach-leaks-subscriptions', () {
    setUp(() => _markerHits = 0);

    test('cancels attach-time service subscriptions when global init attach fails',
        () async {
      final runtime = PluginRuntime(plugins: [_GlobalAttachThrowsPlugin()]);
      addTearDown(() async => runtime.dispose());

      expect(() => runtime.init(), throwsA(isA<PluginLifecycleException>()));
      await runtime.globalBus.emit<_MarkerEvent>(event: const _MarkerEvent());

      expect(_markerHits, 0);
    });
  });
}
