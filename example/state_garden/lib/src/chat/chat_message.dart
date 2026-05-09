/// A single message in the chat protocol.
///
/// Implemented as an immutable value type with structural equality so that
/// state holders (Cubit, ChangeNotifier, AsyncNotifier) can rely on
/// `==` to suppress redundant rebuilds when an unchanged message list is
/// re-emitted. CRITICAL-10 of the Flutter architecture rules requires
/// exposed state types to support value equality.
class ChatMessage {
  const ChatMessage({required this.author, required this.text});

  /// Logical sender. Conventional values: `'user'`, `'bot'`.
  final String author;

  /// Raw text payload.
  final String text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessage &&
          runtimeType == other.runtimeType &&
          author == other.author &&
          text == other.text;

  @override
  int get hashCode => Object.hash(author, text);

  @override
  String toString() => 'ChatMessage(author: $author, text: $text)';
}
