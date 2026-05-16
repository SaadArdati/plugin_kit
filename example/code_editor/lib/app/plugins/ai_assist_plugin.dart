import 'dart:async';

import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';

// Vendor-brand palette for the AI Assist panel interior. These are NOT theme
// tokens — they represent a third-party AI provider's brand identity (a
// Gemini-flavored aurora) and intentionally live outside Theme.of so the
// panel reads as a branded vendor surface no matter what the host app theme
// looks like.
const _geminiBlue = Color(0xFF4285F4);
const _geminiViolet = Color(0xFF9B72CB);
const _geminiPink = Color(0xFFD96570);
const _geminiPeach = Color(0xFFF0975C);
const _geminiInk = Color(0xFFE3E3E3);
const _geminiMutedInk = Color(0xFFB3B3B3);

const _geminiAurora = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_geminiBlue, _geminiViolet, _geminiPink, _geminiPeach],
);

class _ChatMessage {
  final String role;
  String text;
  _ChatMessage({required this.role, required this.text});
}

class AiAssistPlugin extends SessionPlugin {
  static const id = PluginId('ai_assist');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('ai_assist'),
      _AiAssistPanelFactory.new,
      capabilities: const {
        UiConfigurableCapability(
          label: 'AI Assist',
          description: 'Vendor persona and streaming cadence.',
          fields: [
            DropdownConfigField<String>(
              key: 'persona',
              label: 'Persona',
              helperText: 'Voice for canned responses.',
              options: [
                DropdownOption('helpful', 'Helpful'),
                DropdownOption('concise', 'Concise'),
                DropdownOption('verbose', 'Verbose'),
              ],
              defaultValue: 'helpful',
            ),
            NumberConfigField(
              key: 'streamMsPerToken',
              label: 'Stream cadence (ms/token)',
              helperText: 'Lower = faster token reveal.',
              min: 10,
              max: 200,
              step: 10,
              isInteger: true,
              defaultValue: 20,
            ),
          ],
        ),
      },
    );
  }
}

class _AiAssistPanel extends StatefulWidget {
  const _AiAssistPanel({
    required this.messages,
    required this.isStreaming,
    required this.persona,
    required this.onSend,
  });

  final List<_ChatMessage> messages;
  final bool isStreaming;
  final String persona;
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14151A), Color(0xFF1A1B23), Color(0xFF1F1A26)],
        ),
      ),
      child: Column(
        children: [
          _BrandHeader(persona: widget.persona),
          Expanded(
            child: widget.messages.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: widget.messages.length,
                    itemBuilder: (context, i) =>
                        _MessageBubble(message: widget.messages[i]),
                  ),
          ),
          if (widget.isStreaming) const _StreamingIndicator(),
          _Composer(
            controller: _controller,
            enabled: !widget.isStreaming,
            onSubmit: _send,
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.persona});
  final String persona;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x22FFFFFF))),
      ),
      child: Row(
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => _geminiAurora.createShader(rect),
            child: const Icon(Icons.auto_awesome, size: 16),
          ),
          const SizedBox(width: 8),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => _geminiAurora.createShader(rect),
            child: const Text(
              'Gemini',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '· $persona',
            style: const TextStyle(fontSize: 11, color: _geminiMutedInk),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => _geminiAurora.createShader(rect),
            child: const Icon(Icons.auto_awesome, size: 36),
          ),
          const SizedBox(height: 10),
          const Text(
            'Ask anything about your code',
            style: TextStyle(color: _geminiMutedInk, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isUser ? const Color(0x336988FF) : const Color(0x11FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: isUser
            ? null
            : const Border(left: BorderSide(color: _geminiViolet, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!isUser)
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (rect) => _geminiAurora.createShader(rect),
                  child: const Icon(Icons.auto_awesome, size: 12),
                )
              else
                const Icon(Icons.person_outline, size: 12, color: _geminiBlue),
              const SizedBox(width: 6),
              Text(
                isUser ? 'You' : 'Gemini',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _geminiMutedInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message.text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: _geminiInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingIndicator extends StatelessWidget {
  const _StreamingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Row(
        children: [
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) => _geminiAurora.createShader(rect),
            child: const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'Thinking...',
            style: TextStyle(fontSize: 11, color: _geminiMutedInk),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              style: const TextStyle(fontSize: 12, color: _geminiInk),
              decoration: const InputDecoration(
                filled: true,
                fillColor: Color(0x11FFFFFF),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                hintText: 'Ask Gemini...',
                hintStyle: TextStyle(fontSize: 12, color: _geminiMutedInk),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide(color: _geminiViolet),
                ),
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onSubmit : null,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: enabled ? _geminiAurora : null,
                  color: enabled ? null : const Color(0x11FFFFFF),
                ),
                child: const Icon(
                  Icons.arrow_upward,
                  size: 16,
                  color: Colors.white,
                ),
              ),
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

  String get _persona => config.get<String>('persona') ?? 'helpful';
  int get _streamMs => (config.get<num>('streamMsPerToken') ?? 20).toInt();

  @override
  Widget build(BuildContext context) => _AiAssistPanel(
    messages: List.of(_messages),
    isStreaming: _isStreaming,
    persona: _persona,
    onSend: _handleUserMessage,
  );

  @override
  void onSettingsInjected() {
    // Initial injection can run before attach() binds the context; emit only
    // when context is live.
    if (hasContext) emit(const UIRefreshRequest());
  }

  @override
  void attach() {
    on<CollectToolbarActions>((envelope) async {
      envelope.event.actions.add(
        ToolbarActionDescriptor(
          id: 'ai_assist',
          label: 'AI',
          iconCodePoint: Icons.auto_awesome.codePoint,
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
    _streamTimer = Timer.periodic(Duration(milliseconds: _streamMs), (
      timer,
    ) async {
      if (charIndex < response.length) {
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
