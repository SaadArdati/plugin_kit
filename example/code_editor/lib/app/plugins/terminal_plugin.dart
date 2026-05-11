import 'dart:async';

import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';
import '../theme.dart';

class _TerminalPanel extends StatefulWidget {
  const _TerminalPanel({required this.history, required this.onCommand});

  final List<TerminalLine> history;
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
    return Container(
      color: EditorColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              itemCount: widget.history.length,
              itemBuilder: (context, i) {
                final line = widget.history[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    line.isPrompt ? '\$ ${line.text}' : line.text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: line.isPrompt
                          ? EditorColors.success
                          : line.isError
                          ? EditorColors.error
                          : line.isSuccess
                          ? EditorColors.success
                          : EditorColors.textPrimary,
                      fontWeight: line.isPrompt
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              children: [
                Text(
                  '\$ ',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: EditorColors.success,
                  ),
                ),
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
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: EditorColors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                        border: InputBorder.none,
                        hintText: 'Type a command...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: EditorColors.textMuted,
                        ),
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

  @override
  Widget build(BuildContext context) =>
      _TerminalPanel(history: List.of(_history), onCommand: _handleCommand);

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

    await emit(const UIRefreshRequest());
  }

  /// `dart run` triggers the Runner plugin, `dart analyze` fakes linting.
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

class TerminalPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('terminal');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('terminal'),
      () => _TerminalPanelFactory(),
    );
  }
}
