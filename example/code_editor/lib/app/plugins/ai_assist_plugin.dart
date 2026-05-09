import 'dart:async';

import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';
import '../theme.dart';

class _ChatMessage {
  final String role; // 'user' or 'assistant'
  String text;
  _ChatMessage({required this.role, required this.text});
}

class _AiAssistPanel extends StatefulWidget {
  const _AiAssistPanel({
    required this.messages,
    required this.isStreaming,
    required this.onSend,
  });

  final List<_ChatMessage> messages;
  final bool isStreaming;
  final void Function(String) onSend;

  @override
  State<_AiAssistPanel> createState() => _AiAssistPanelState();
}

class _AiAssistPanelState extends State<_AiAssistPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(_AiAssistPanel old) {
    super.didUpdateWidget(old);
    if (widget.messages.length != old.messages.length || widget.isStreaming) {
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
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isStreaming) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Subtle branded background
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [EditorColors.canvas, EditorColors.surface],
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EditorColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: EditorColors.warning),
                const SizedBox(width: 6),
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: EditorColors.warning,
                  ),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: widget.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 40,
                          color: EditorColors.warning.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ask anything about your code',
                          style: TextStyle(
                            color: EditorColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, i) {
                      final msg = widget.messages[i];
                      final isUser = msg.role == 'user';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isUser
                              ? EditorColors.accentMuted.withValues(alpha: 0.3)
                              : EditorColors.hoverOverlay,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUser ? 'You' : 'Assistant',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isUser
                                    ? EditorColors.info
                                    : EditorColors.warning,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              msg.text,
                              style: const TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Streaming indicator
          if (widget.isStreaming)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: EditorColors.warning,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      fontSize: 11,
                      color: EditorColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

          // Input
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: EditorColors.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      hintText: 'Ask a question...',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: EditorColors.textMuted,
                      ),
                      filled: true,
                      fillColor: EditorColors.hoverOverlay,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                    enabled: !widget.isStreaming,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, size: 18),
                  color: EditorColors.warning,
                  onPressed: widget.isStreaming ? null : _send,
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
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

class _AiAssistPanelFactory extends SessionStatefulPluginService
    implements PanelWidgetFactory {
  final List<_ChatMessage> _messages = [];
  var _isStreaming = false;
  Timer? _streamTimer;
  var _responseIndex = 0;

  @override
  Widget build(BuildContext context) => _AiAssistPanel(
    messages: List.of(_messages),
    isStreaming: _isStreaming,
    onSend: _handleUserMessage,
  );

  @override
  void attach() {
    on<CollectToolbarActions>((envelope) async {
      envelope.event.actions.add(
        ToolbarActionDescriptor(
          id: 'ai_assist',
          label: 'AI',
          iconCodePoint: Icons.auto_awesome.codePoint,
          colorValue: EditorColors.warning.toARGB32(),
        ),
      );
    });

    on<CollectPanels>((envelope) async {
      envelope.event.panels.add(
        const PanelDescriptor(
          id: 'ai_assist',
          title: 'AI Assist',
          position: PanelPosition.right,
        ),
      );
    });

    on<ToolbarActionTriggered>((event) async {
      if (event.event.actionId == 'ai_assist') {
        await emit(const TogglePanelRequest('ai_assist'));
      }
    });
  }

  Future<void> _handleUserMessage(String text) async {
    _messages.add(_ChatMessage(role: 'user', text: text));
    _isStreaming = true;
    await emit(const UIRefreshRequest());

    final response =
        aiAssistCannedResponses[_responseIndex %
            aiAssistCannedResponses.length];
    _responseIndex++;

    final assistantMsg = _ChatMessage(role: 'assistant', text: '');
    _messages.add(assistantMsg);
    var charIndex = 0;

    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(const Duration(milliseconds: 20), (
      timer,
    ) async {
      if (charIndex < response.length) {
        // A few chars at a time for speed.
        final end = (charIndex + 3).clamp(0, response.length);
        assistantMsg.text = response.substring(0, end);
        charIndex = end;
        await emit(const UIRefreshRequest());
      } else {
        timer.cancel();
        _isStreaming = false;
        await emit(const UIRefreshRequest());
      }
    });
  }

  @override
  Future<void> detach() async {
    _streamTimer?.cancel();
  }
}

class AiAssistPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('ai_assist');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('ai_assist'),
      _AiAssistPanelFactory(),
    );
  }
}
