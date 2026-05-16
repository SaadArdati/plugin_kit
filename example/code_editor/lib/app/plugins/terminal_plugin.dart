import 'dart:async';

import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';

class TerminalPlugin extends SessionPlugin {
  static const id = PluginId('terminal');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('terminal'),
      _TerminalPanelFactory.new,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Terminal',
          description: 'Shell prompt and history retention.',
          fields: [
            TextConfigField(
              key: 'prompt',
              label: 'Prompt',
              helperText: 'Prefix shown for input and emitted command lines.',
              defaultValue: '\$ ',
            ),
            NumberConfigField(
              key: 'maxHistory',
              label: 'Max history lines',
              helperText: 'Older lines are trimmed when this is exceeded.',
              min: 50,
              max: 500,
              step: 50,
              isInteger: true,
              defaultValue: 200,
            ),
          ],
        ),
      },
    );
  }
}

class _TerminalPanel extends StatefulWidget {
  const _TerminalPanel({
    required this.history,
    required this.prompt,
    required this.onCommand,
  });

  final List<TerminalLine> history;
  final String prompt;
  final void Function(String command) onCommand;

  @override
  State<_TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<_TerminalPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  @override
  void didUpdateWidget(_TerminalPanel old) {
    super.didUpdateWidget(old);
    if (widget.history.length != old.history.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty) return;
    _controller.clear();
    widget.onCommand(cmd);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    final promptStyle = mono?.copyWith(
      color: theme.colorScheme.tertiary,
      fontWeight: FontWeight.w600,
    );
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              itemCount: widget.history.length,
              itemBuilder: (context, i) {
                final line = widget.history[i];
                final color = line.isError
                    ? theme.colorScheme.error
                    : line.isSuccess
                    ? theme.colorScheme.tertiary
                    : line.isPrompt
                    ? theme.colorScheme.tertiary
                    : theme.colorScheme.onSurface;
                final text = line.isPrompt
                    ? '${widget.prompt}${line.text}'
                    : line.text;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    text,
                    style: mono?.copyWith(
                      color: color,
                      fontWeight: line.isPrompt
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(widget.prompt, style: promptStyle),
                Expanded(
                  child: KeyboardListener(
                    focusNode: _focusNode,
                    onKeyEvent: (event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        _submit();
                      }
                    },
                    child: TextField(
                      controller: _controller,
                      style: mono,
                      decoration: const InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isCollapsed: true,
                        hintText: 'Type a command...',
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalPanelFactory extends SessionStatefulPluginService
    implements PanelWidgetFactory {
  final List<TerminalLine> _history = [];

  String get _prompt => config.get<String>('prompt') ?? '\$ ';
  int get _maxHistory => (config.get<num>('maxHistory') ?? 200).toInt();

  void _trim() {
    final overflow = _history.length - _maxHistory;
    if (overflow > 0) _history.removeRange(0, overflow);
  }

  @override
  Widget build(BuildContext context) => _TerminalPanel(
    history: List.of(_history),
    prompt: _prompt,
    onCommand: _handleCommand,
  );

  @override
  void onSettingsInjected() {
    _trim();
    // Initial injection can run before attach() binds the context; emit only
    // when context is live.
    if (hasContext) emit(const UIRefreshRequest());
  }

  @override
  void attach() {
    on<CollectPanels>((envelope) async {
      envelope.event.panels.add(
        PanelDescriptor(
          id: 'terminal',
          title: 'Terminal',
          position: PanelPosition.bottom,
          iconCodePoint: Icons.terminal.codePoint,
        ),
      );
    });
  }

  Future<void> _handleCommand(String command) async {
    _history.add(TerminalLine(command, isPrompt: true));

    final parts = command.trim().split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();

    switch (cmd) {
      case 'dart':
        await _handleDart(parts);

      case 'ls':
        _history.addAll(terminalLsOutput);

      case 'pwd':
        _history.add(terminalPwdOutput);

      case 'git':
        _handleGit(parts);

      case 'clear':
        _history.clear();

      case 'help':
        _history.addAll(terminalHelpOutput);

      default:
        _history.add(
          TerminalLine(
            '$cmd: command not found. Type "help" for available commands.',
            isError: true,
          ),
        );
    }

    _trim();
    await emit(const UIRefreshRequest());
  }

  Future<void> _handleDart(List<String> parts) async {
    if (parts.length < 2) {
      _history.add(const TerminalLine('Usage: dart <run|analyze|test>'));
      return;
    }

    switch (parts[1]) {
      case 'run':
        _history.add(
          const TerminalLine('Triggering Runner plugin...', isSuccess: true),
        );
        await emit(const ToolbarActionTriggered('run'));

      case 'analyze':
        _history.addAll(terminalDartAnalyzeOutput);

      case 'test':
        _history.addAll(terminalDartTestOutput);

      default:
        _history.add(const TerminalLine('Usage: dart <run|analyze|test>'));
    }
  }

  void _handleGit(List<String> parts) {
    if (parts.length < 2) {
      _history.add(const TerminalLine('Usage: git <status|log>'));
      return;
    }

    switch (parts[1]) {
      case 'status':
        _history.addAll(terminalGitStatusOutput);

      case 'log':
        _history.addAll(terminalGitLogOutput);

      default:
        _history.add(const TerminalLine('Usage: git <status|log>'));
    }
  }
}
