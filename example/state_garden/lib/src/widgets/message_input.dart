import 'package:flutter/material.dart';

/// Text field plus send button, isolated as its own stateful widget so the
/// `TextEditingController` lifecycle is owned at exactly one site.
///
/// Calls [onSubmit] with the trimmed text on tap, then clears the field.
/// Empty submissions are dropped.
class MessageInput extends StatefulWidget {
  const MessageInput({super.key, required this.onSubmit});

  final Future<void> Function(String text) onSubmit;

  static const Key fieldKey = Key('input');
  static const Key sendButtonKey = Key('send');

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              key: MessageInput.fieldKey,
              controller: _controller,
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          IconButton(
            key: MessageInput.sendButtonKey,
            icon: const Icon(Icons.send),
            onPressed: _handleSend,
          ),
        ],
      ),
    );
  }
}
