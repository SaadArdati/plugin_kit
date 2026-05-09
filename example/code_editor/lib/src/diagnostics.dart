/// Severity levels for diagnostics, ordered from most to least severe.
enum DiagnosticSeverity { error, warning, info, hint }

/// A single diagnostic reported by a linter or language service.
///
/// [line] is 1-indexed (line 1 is the first line of the document).
/// [source] identifies which plugin produced the diagnostic.
class Diagnostic {
  final int line;
  final DiagnosticSeverity severity;
  final String message;
  final String source;

  const Diagnostic({
    required this.line,
    required this.severity,
    required this.message,
    required this.source,
  });

  @override
  String toString() {
    final tag = severity.name.toUpperCase();
    return '  [$tag] line $line ($source): $message';
  }
}
