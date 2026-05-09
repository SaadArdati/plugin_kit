/// # 10: Full Editor CLI
///
/// Capstone. Five behavior plugins ([SqlLanguagePlugin], [DartLanguagePlugin],
/// [MarkdownLanguagePlugin], [FormatterPipelinePlugin], [LinterSuitePlugin])
/// run together while main exercises the full lifecycle: open documents,
/// analyze, format, save, request completions, disable a plugin via
/// settings, re-enable, save again.
///
/// A local `DiagnosticCollectorPlugin` exposes a per-file diagnostic map
/// so main can read what [LinterSuitePlugin] published on each
/// [DocumentSavedEvent] without subscribing to the bus itself.
///
/// Every behavior plugin owns its bus subscriptions through
/// `StatefulPluginService`s, so `updateSessionSettings` cleanly detaches
/// them on disable and re-attaches them on re-enable. The example disables
/// `linter_suite`, emits saves while disabled (expecting zero diagnostics),
/// re-enables, and emits saves again (expecting diagnostics flow).
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/plugins/dart_language.dart';
import 'package:code_editor/plugins/formatter_pipeline.dart';
import 'package:code_editor/plugins/linter_suite.dart';
import 'package:code_editor/plugins/markdown_language.dart';
import 'package:code_editor/plugins/sql_language.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Per-file diagnostic sink. Owns its own subscription via
/// `StatefulPluginService`. Appends on every publish so multiple
/// publishers for the same file don't clobber one another.
class DiagnosticCollector extends SessionStatefulPluginService {
  final Map<String, List<Diagnostic>> byFile = {};

  @override
  void attach() {
    on<DiagnosticPublishedEvent>((event) {
      byFile
          .putIfAbsent(event.event.filename, () => [])
          .addAll(event.event.diagnostics);
    });
  }
}

class DiagnosticCollectorPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('diagnostic_collector');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<DiagnosticCollector>(
      const ServiceId('diagnostic_collector'),
      DiagnosticCollector(),
    );
  }
}

final _sqlDoc = TextDocument(
  filename: 'query.sql',
  content:
      'select   id, name, email   \n'
      'from   accounts   \n'
      'where  active = true   \n'
      'order by   name   ',
  languageId: 'sql',
);

final _dartDoc = TextDocument(
  filename: 'app.dart',
  content:
      '// TODO: migrate to null-safety\n'
      'class AppConfig {\n'
      '  // TODO: add validation\n'
      '  final String apiUrl;\n'
      '  final String apiKey = "some-very-long-api-key-value-that-exceeds-the-default-eighty-char-limit";\n'
      '  AppConfig({required this.apiUrl});\n'
      '}',
  languageId: 'dart',
);

final _mdDoc = TextDocument(
  filename: 'README.md',
  content:
      '# Editor Plugin Kit\n\n'
      'See [the guide](https://example.com/guide) and '
      '[the API docs](https://example.com/api) for details.\n\n'
      '## Quick Start\n\n'
      '```dart\nvoid main() {}\n```\n',
  languageId: 'markdown',
);

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [
      SqlLanguagePlugin(),
      DartLanguagePlugin(),
      MarkdownLanguagePlugin(),
      FormatterPipelinePlugin(),
      LinterSuitePlugin(),
      DiagnosticCollectorPlugin(),
    ],
  )..init();

  final session = await runtime.createSession();
  final registry = session.registry;

  final collector = registry.resolve<DiagnosticCollector>(
    const ServiceId('diagnostic_collector'),
  );
  final diagnosticsByFile = collector.byFile;

  print('=== Opening documents ===');
  for (final doc in [_sqlDoc, _dartDoc, _mdDoc]) {
    await session.emit(DocumentOpenedEvent(doc));
    print('  Opened: ${doc.filename} (${doc.languageId})');
  }
  print('');

  print('=== Analysis ===');

  final sqlAnalyzer = registry.resolve<SqlAnalyzer>(
    const ServiceId('sql_analyzer'),
  );
  final dartAnalyzer = registry.resolve<DartAnalyzer>(
    const ServiceId('dart_analyzer'),
  );
  final mdAnalyzer = registry.resolve<MarkdownAnalyzer>(
    const ServiceId('markdown_analyzer'),
  );

  for (final (doc, analyzer) in [
    (_sqlDoc, sqlAnalyzer as LanguageService),
    (_dartDoc, dartAnalyzer as LanguageService),
    (_mdDoc, mdAnalyzer as LanguageService),
  ]) {
    final results = analyzer.analyze(doc);
    print('${doc.filename}:');
    for (final d in results) {
      print(d);
    }
  }
  print('');

  print('=== Formatting query.sql ===');
  print('Before:');
  for (final line in _sqlDoc.lines) {
    print('  |$line|');
  }

  await session.emit(FormatDocumentEvent(_sqlDoc));

  print('After:');
  for (final line in _sqlDoc.lines) {
    print('  |$line|');
  }
  print('');

  print('=== Saving all documents ===');
  diagnosticsByFile.clear();

  for (final doc in [_sqlDoc, _dartDoc, _mdDoc]) {
    await session.emit(DocumentSavedEvent(doc));
  }

  _printAllDiagnostics(diagnosticsByFile);

  print('=== Completions for query.sql ===');
  final completionResponse = await session
      .request<CompletionRequest, CompletionResponse?>(
        CompletionRequest(document: _sqlDoc, line: 0, column: 0),
      );

  if (completionResponse != null) {
    print('${completionResponse.items.length} item(s):');
    for (final item in completionResponse.items.take(5)) {
      print('  $item');
    }
    if (completionResponse.items.length > 5) {
      print('  … (${completionResponse.items.length - 5} more)');
    }
  } else {
    print('  (no completions)');
  }
  print('');

  // Disable linter_suite via settings update. Its save handler lives on a
  // StatefulPluginService (`_LinterSaveHook`), so `updateSessionSettings`
  // calls the service's detach and the subscription is cancelled. We
  // verify by emitting a save WHILE DISABLED: no diagnostics should flow.
  print('=== Disabling linter_suite ===');
  final settingsWithoutLinter = RuntimeSettings(
    plugins: {PluginId('linter_suite'): PluginConfig(enabled: false)},
  );

  await runtime.updateSessionSettings(
    session,
    newSettings: settingsWithoutLinter,
  );

  print(
    'linter_suite enabled: ${session.isPluginEnabled(const PluginId('linter_suite'))}',
  );

  diagnosticsByFile.clear();
  for (final doc in [_sqlDoc, _dartDoc, _mdDoc]) {
    await session.emit(DocumentSavedEvent(doc));
  }
  // sql_language is still enabled, so it still publishes diagnostics for
  // .sql. The linter_suite TODO/line-length checks should be absent.
  final linterSources = {'todo_linter', 'line_length_linter'};
  final linterDiagnostics = diagnosticsByFile.values
      .expand((list) => list)
      .where((d) => linterSources.contains(d.source))
      .toList();
  if (linterDiagnostics.isNotEmpty) {
    throw StateError(
      'Settings reconciliation regressed: linter_suite produced '
      '${linterDiagnostics.length} diagnostics while disabled',
    );
  }
  print('linter_suite diagnostics while disabled: 0');
  print('');

  // Re-enable and emit saves again. The plugin's register + attach run,
  // which re-creates its StatefulPluginServices and their subscriptions.
  print('=== Re-enabling linter_suite ===');
  final settingsWithLinter = RuntimeSettings();

  await runtime.updateSessionSettings(session, newSettings: settingsWithLinter);

  print(
    'linter_suite enabled: ${session.isPluginEnabled(const PluginId('linter_suite'))}',
  );
  print('');

  diagnosticsByFile.clear();
  for (final doc in [_sqlDoc, _dartDoc, _mdDoc]) {
    await session.emit(DocumentSavedEvent(doc));
  }

  print('Diagnostics after re-enabling linter_suite:');
  _printAllDiagnostics(diagnosticsByFile);

  await runtime.dispose();
  print('=== Done ===');
}

void _printAllDiagnostics(Map<String, List<Diagnostic>> byFile) {
  if (byFile.isEmpty) {
    print('  (no diagnostics)');
    print('');
    return;
  }
  for (final entry in byFile.entries) {
    final file = entry.key;
    final diags = entry.value;
    if (diags.isEmpty) continue;
    print('$file (${diags.length} diagnostic(s)):');
    final sorted = [...diags]
      ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
    for (final d in sorted) {
      print(d);
    }
  }
  print('');
}
