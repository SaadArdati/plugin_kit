/// Debug adapter: tracks breakpoints, steps, and state transitions.
///
/// Registers a [StatefulPluginService] that subscribes to [DebugEvent]
/// and maintains session state across the debug lifecycle.
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

class DebugAdapterService extends SessionStatefulPluginService {
  DebugAdapterService();

  DebugState _state = DebugState.idle;
  int _breakpointHitCount = 0;
  int _stepCount = 0;

  @override
  void attach() {
    _state = DebugState.idle;
    _breakpointHitCount = 0;
    _stepCount = 0;

    on<DebugEvent>((event) {
      switch (event.event.action) {
        case DebugAction.start:
          _state = DebugState.running;
          print('[Debug] Session started');
        case DebugAction.breakpointHit:
          _state = DebugState.paused;
          _breakpointHitCount++;
          print('[Debug] Breakpoint hit at ${event.event.breakpoint}');
        case DebugAction.step:
          _state = DebugState.running;
          _stepCount++;
          print('[Debug] Step (total: $_stepCount)');
        case DebugAction.resume:
          _state = DebugState.running;
          print('[Debug] Resumed');
        case DebugAction.pause:
          _state = DebugState.paused;
          print('[Debug] Paused');
        case DebugAction.stop:
          _state = DebugState.stopped;
          print('[Debug] Session stopped');
      }
    });
  }

  @override
  Future<void> detach() async {
    print(
      '[Debug] Adapter detached. Stats: $_breakpointHitCount breakpoints hit, $_stepCount steps taken',
    );
  }

  DebugState get state => _state;
}

class DebuggerPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('debugger');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<DebugAdapterService>(
      const ServiceId('debug_adapter'),
      DebugAdapterService(),
    );
  }

  // attach/detach are handled automatically by the base Plugin class
  // because DebugAdapterService extends StatefulPluginService.
}
