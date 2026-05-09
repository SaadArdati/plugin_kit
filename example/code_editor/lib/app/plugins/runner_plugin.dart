import 'dart:async';

import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';
import '../theme.dart';

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({required this.lines, required this.isRunning});

  final List<String> lines;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EditorColors.canvas,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRunning)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: EditorColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Running...',
                    style: TextStyle(
                      color: EditorColors.success,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: lines.isEmpty && !isRunning
                ? Center(
                    child: Text(
                      'Press Run to start',
                      style: TextStyle(
                        color: EditorColors.textMuted,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (context, i) {
                      final line = lines[i];
                      final isError =
                          line.startsWith('Error') || line.startsWith('!');
                      final isSuccess =
                          line.startsWith('✓') || line.contains('completed');
                      return Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isError
                              ? EditorColors.error
                              : isSuccess
                              ? EditorColors.success
                              : EditorColors.textPrimary,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConsolePanelFactory extends SessionStatefulPluginService
    implements PanelWidgetFactory {
  var _lines = <String>[];
  var _isRunning = false;
  Timer? _timer;
  var _outputIndex = 0;

  @override
  Widget build(BuildContext context) =>
      _ConsolePanel(lines: List.of(_lines), isRunning: _isRunning);

  @override
  void attach() {
    on<CollectToolbarActions>((envelope) async {
      envelope.event.actions.add(
        ToolbarActionDescriptor(
          id: _isRunning ? 'stop' : 'run',
          label: _isRunning ? 'Stop' : 'Run',
          iconCodePoint: _isRunning
              ? Icons.stop.codePoint
              : Icons.play_arrow.codePoint,
          colorValue: _isRunning
              ? EditorColors.error.toARGB32()
              : EditorColors.success.toARGB32(),
        ),
      );
    });

    on<CollectPanels>((envelope) async {
      envelope.event.panels.add(
        PanelDescriptor(
          id: 'console',
          title: 'Console',
          position: PanelPosition.bottom,
          iconCodePoint: Icons.terminal.codePoint,
        ),
      );
    });

    on<CollectStatusBarItems>((envelope) async {
      if (_isRunning) {
        envelope.event.items.add(
          StatusBarDescriptor(
            id: 'runner_status',
            text: 'Running...',
            iconCodePoint: Icons.play_arrow.codePoint,
          ),
        );
      }
    });

    on<ToolbarActionTriggered>((event) async {
      if (event.event.actionId == 'run') {
        await _startRun();
      } else if (event.event.actionId == 'stop') {
        await _stopRun();
      }
    });
  }

  Future<void> _startRun() async {
    _isRunning = true;
    _outputIndex = 0;
    _lines = [];
    await emit(const UIRefreshRequest());

    _timer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (_outputIndex < runnerFakeOutput.length) {
        _lines.add(runnerFakeOutput[_outputIndex]);
        _outputIndex++;
        await emit(const UIRefreshRequest());
      } else {
        await _stopRun();
      }
    });
  }

  Future<void> _stopRun() async {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    if (_outputIndex < runnerFakeOutput.length) {
      _lines.add('! Process terminated.');
    }
    await emit(const UIRefreshRequest());
  }

  @override
  Future<void> detach() async {
    _timer?.cancel();
  }
}

class RunnerPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('runner');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('console'),
      _ConsolePanelFactory(),
    );
  }
}
