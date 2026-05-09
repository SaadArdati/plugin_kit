/// A document open in the editor.
///
/// `content` is mutable: formatter plugins modify it in place during the
/// `FormatDocumentEvent` handler chain. `filename` and `languageId` are
/// immutable identifiers.
class TextDocument {
  final String filename;
  String content;
  final String languageId;

  TextDocument({
    required this.filename,
    required this.content,
    required this.languageId,
  });

  List<String> get lines => content.split('\n');
  int get lineCount => lines.length;

  @override
  String toString() => 'TextDocument($filename, $languageId, $lineCount lines)';
}
