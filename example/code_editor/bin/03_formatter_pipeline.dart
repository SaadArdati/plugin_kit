/// # 03: Formatter Pipeline
///
/// Plugin dependencies composing a priority-ordered handler chain.
///
/// [FormatterPipelinePlugin] is the base: trim trailing whitespace
/// (priority 0) and enforce a single trailing newline (priority 10).
/// [SqlFormatterPlugin] and [DartFormatterPlugin] declare it as a
/// dependency and inject language-specific stages between those bookends.
///
/// Three phases demonstrate what each plugin contributes.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/formatter_pipeline.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  // Phase 1: full pipeline, SQL document.
  print('=== Phase 1: Full pipeline on .sql ===\n');

  var runtime = PluginRuntime(
    plugins: [
      FormatterPipelinePlugin(),
      SqlFormatterPlugin(),
      DartFormatterPlugin(),
    ],
  )..init();
  var session = await runtime.createSession();

  final sqlDoc = TextDocument(
    filename: 'query.sql',
    content: messySql,
    languageId: 'sql',
  );
  await _formatAndPrint(session, sqlDoc);

  // Phase 2: same runtime, Dart document. The Dart hook re-indents.
  print('\n=== Phase 2: Full pipeline on .dart ===\n');

  final dartDoc = TextDocument(
    filename: 'main.dart',
    content: messyDart,
    languageId: 'dart',
  );
  await _formatAndPrint(session, dartDoc);

  await runtime.dispose();

  // Phase 3: drop SqlFormatterPlugin. Base stages still trim trailing
  // whitespace and ensure a trailing newline, but keywords stay lowercase
  // and internal whitespace runs survive.
  print('\n=== Phase 3: Base only (no SqlFormatterPlugin) on .sql ===\n');

  runtime = PluginRuntime(
    plugins: [FormatterPipelinePlugin(), DartFormatterPlugin()],
  )..init();
  session = await runtime.createSession();

  final baseOnlySqlDoc = TextDocument(
    filename: 'query.sql',
    content: messySql,
    languageId: 'sql',
  );
  await _formatAndPrint(session, baseOnlySqlDoc);

  await runtime.dispose();
}

Future<void> _formatAndPrint(PluginSession session, TextDocument doc) async {
  print('Before (${doc.filename}):');
  for (final line in doc.lines) {
    print('  |$line|');
  }
  print('');

  await session.emit(FormatDocumentEvent(doc));

  print('After:');
  for (final line in doc.lines) {
    print('  |$line|');
  }
}
