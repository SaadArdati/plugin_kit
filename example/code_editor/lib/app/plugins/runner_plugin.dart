import 'dart:async';

import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';

class RunnerPlugin extends SessionPlugin {
  static const id = PluginId('runner');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('console'),
      _ConsolePanelFactory.new,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Runner',
          description: 'Console output cadence and reset behavior.',
          fields: [
            NumberConfigField(
              key: 'tickMs',
              label: 'Tick interval (ms)',
              helperText: 'Delay between mock output lines while running.',
              min: 100,
              max: 1000,
              step: 50,
              isInteger: true,
              defaultValue: 300,
            ),
            BoolConfigField(
              key: 'autoClearOnRun',
              label: 'Auto-clear on Run',
              helperText: 'Wipe the console each time you press Run.',
              defaultValue: true,
            ),
          ],
        ),
      },
    );
  }
}

class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel({required this.lines, required this.isRunning});

  final List<String> lines;
  final bool isRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRunning)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Running...',
                    style: mono?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                ],
              ),
            ),
          Expanded(
            child: lines.isEmpty && !isRunning
                ? Center(
                    child: Text(
                      'Press Run to start',
                      style: mono?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
                      final color = isError
                          ? theme.colorScheme.error
                          : isSuccess
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurface;
                      return Text(line, style: mono?.copyWith(color: color));
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

  int get _tickMs => (config.get<num>('tickMs') ?? 300).toInt();
  bool get _autoClear => config.get<bool>('autoClearOnRun') ?? true;

  @override
  Widget build(BuildContext context) =>
      _ConsolePanel(lines: List.of(_lines), isRunning: _isRunning);

  @override
  void onSettingsInjected() {
    // Initial injection can run before attach() binds the context; emit only
    // when context is live. Subsequent injections (via updateSessionSettings)
    // happen with context bound, so the live editor sees the refresh.
    if (hasContext) emit(const UIRefreshRequest());
  }

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
              ? const Color(0xFFE55765).toARGB32()
              : const Color(0xFF57A64A).toARGB32(),
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
    if (_autoClear) _lines = [];
    await emit(const UIRefreshRequest());

    _timer = Timer.periodic(Duration(milliseconds: _tickMs), (timer) async {
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
