/// # 07: Debugger Lifecycle
///
/// A [StatefulPluginService] that lives for the duration of a session.
///
/// [DebuggerPlugin] registers [DebugAdapterService]. The service reacts
/// to [DebugEvent]s and tracks breakpoint hits and step counts. On detach
/// (session dispose), it prints aggregate stats.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/plugins/debugger.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [DebuggerPlugin()])..init();
  final session = await runtime.createSession();

  final adapter = session.registry.resolve<DebugAdapterService>(
    const ServiceId('debug_adapter'),
  );

  print('Initial state: ${adapter.state}');
  print('');

  Future<void> emit(DebugEvent event, String label) async {
    await session.emit(event);
    print('  state after $label: ${adapter.state}');
  }

  print('--- Emitting debug events ---');
  await emit(const DebugEvent(DebugAction.start), 'start');
  print('');

  await emit(
    const DebugEvent(
      DebugAction.breakpointHit,
      breakpoint: Breakpoint(filename: 'main.dart', line: 42),
    ),
    'breakpointHit(42)',
  );
  print('');

  for (var i = 1; i <= 3; i++) {
    await emit(const DebugEvent(DebugAction.step), 'step $i');
  }
  print('');

  await emit(
    const DebugEvent(
      DebugAction.breakpointHit,
      breakpoint: Breakpoint(filename: 'main.dart', line: 58),
    ),
    'breakpointHit(58)',
  );
  print('');

  await emit(const DebugEvent(DebugAction.resume), 'resume');
  print('');

  await emit(const DebugEvent(DebugAction.stop), 'stop');
  print('');

  // Dispose. DebugAdapterService.detach prints the aggregate stats.
  print('--- Disposing session ---');
  await runtime.dispose();
}
