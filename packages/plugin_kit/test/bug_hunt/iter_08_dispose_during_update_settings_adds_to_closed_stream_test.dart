import 'dart:async';

import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

class _BlockingService
    extends GlobalStatefulPluginService<GlobalPluginContext> {
  _BlockingService(this.started, this.release);
  final Completer<void> started;
  final Completer<void> release;
  int _detachCalls = 0;

  @override
  Future<void> detach() async {
    if (++_detachCalls == 1) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
  }
}

class _BlockingPlugin extends GlobalPlugin {
  _BlockingPlugin(this.service);
  final _BlockingService service;

  @override
  PluginId get pluginId => const PluginId('g');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_BlockingService>(
      const ServiceId('svc'),
      () => service,
    );
  }
}

void main() {
  group(
    'bug-hunt iter 8: dispose-during-update-settings-adds-to-closed-stream',
    () {
      test(
        'keeps stored settings unchanged when dispose races an in-flight updateSettings',
        () async {
          final started = Completer<void>(), release = Completer<void>();
          final runtime = PluginRuntime(
            plugins: [_BlockingPlugin(_BlockingService(started, release))],
          )..init();
          final beforeDispose = runtime.settings;
          final update = runtime.updateSettings(
            RuntimeSettings(
              services: {
                Pin('g', ['svc']): const ServiceSettings(enabled: false),
              },
            ),
          );

          await started.future;
          await runtime.dispose();
          release.complete();

          await expectLater(update, throwsA(isA<StateError>()));
          expect(runtime.settings, equals(beforeDispose));
        },
      );
    },
  );
}
