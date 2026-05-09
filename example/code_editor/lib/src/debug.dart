class Breakpoint {
  final String filename;
  final int line;
  const Breakpoint({required this.filename, required this.line});

  @override
  String toString() => 'Breakpoint($filename:$line)';
}

enum DebugState { idle, running, paused, stopped }

enum DebugAction { start, pause, resume, step, stop, breakpointHit }

class DebugEvent {
  final DebugAction action;
  final Breakpoint? breakpoint;
  const DebugEvent(this.action, {this.breakpoint});
}
