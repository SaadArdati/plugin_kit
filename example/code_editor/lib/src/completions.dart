import 'documents.dart';

/// A code completion suggestion.
///
/// [label] is the display text shown in the completion menu.
/// [insertText] is what gets inserted into the document on selection.
/// [detail] is a short description (e.g., "SQL keyword").
class CompletionItem {
  final String label;
  final String insertText;
  final String detail;
  const CompletionItem({
    required this.label,
    required this.insertText,
    required this.detail,
  });

  @override
  String toString() => '$label: $detail';
}

/// Request completions at a cursor position within a document.
class CompletionRequest {
  final TextDocument document;
  final int line;
  final int column;
  const CompletionRequest({
    required this.document,
    required this.line,
    required this.column,
  });
}

/// Response carrying zero or more [CompletionItem]s.
class CompletionResponse {
  final List<CompletionItem> items;
  const CompletionResponse(this.items);
}
