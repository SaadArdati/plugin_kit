/// # 04: Diagnostics
///
/// When a document is saved, linter plugins run and emit
/// [DiagnosticPublishedEvent]. Anything interested subscribes directly.
///
/// [LinterSuitePlugin] owns a `TodoLinter` and a `LineLengthLinter`. On
/// every [DocumentSavedEvent] it runs both, combines the results, and
/// emits one [DiagnosticPublishedEvent]. Main subscribes directly and
/// prints the collected diagnostics sorted by severity.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/linter_suite.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [LinterSuitePlugin()])..init();
  final session = await runtime.createSession();

  final collected = <Diagnostic>[];
  session.on<DiagnosticPublishedEvent>((e) {
    collected.addAll(e.event.diagnostics);
  });

  final doc = TextDocument(
    filename: 'my_widget.dart',
    content: dartSourceWithTodos,
    languageId: 'dart',
  );

  await session.emit(DocumentSavedEvent(doc));

  // Errors first, then warnings, info, hints.
  collected.sort((a, b) => a.severity.index.compareTo(b.severity.index));

  print('Diagnostics for ${doc.filename} (${collected.length} total):');
  print('');
  for (final d in collected) {
    print(d);
  }

  await runtime.dispose();
}
