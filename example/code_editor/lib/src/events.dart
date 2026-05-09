import 'diagnostics.dart';
import 'documents.dart';

/// Emitted when a document is opened in the editor for the first time
/// (initial load, new tab, external open).
class DocumentOpenedEvent {
  final TextDocument document;
  const DocumentOpenedEvent(this.document);
}

/// Emitted when focus switches to an already-open document (e.g., tab
/// switch, shell re-sync). Distinct from [DocumentOpenedEvent]: no new
/// document is being opened; a previously-opened document is becoming
/// active. Plugins that render per-active-document state (minimap,
/// outline) listen to both.
class DocumentFocusedEvent {
  final TextDocument document;
  const DocumentFocusedEvent(this.document);
}

/// Emitted when a document is saved. Linter plugins subscribe to this
/// to run diagnostics on the saved content.
class DocumentSavedEvent {
  final TextDocument document;
  const DocumentSavedEvent(this.document);
}

/// Emitted to request formatting. Handlers modify `document.content` in
/// place, so changes accumulate as the cascade runs in priority order
/// (lowest priority number runs first).
class FormatDocumentEvent {
  final TextDocument document;
  const FormatDocumentEvent(this.document);
}

/// Emitted by linters with their diagnostic results after a save event.
class DiagnosticPublishedEvent {
  final String filename;
  final List<Diagnostic> diagnostics;
  const DiagnosticPublishedEvent(this.filename, this.diagnostics);
}
