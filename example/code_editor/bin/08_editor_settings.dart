/// # 08: Editor Settings
///
/// `ConfigNode`, `RuntimeSettings`, and wildcard service overrides.
///
/// `LineLengthLinter` reads its `max_line_length` threshold from injected
/// settings via `PluginService.config`. Three scenarios:
///
/// 1. Default (max 80). An 85-char line is flagged.
/// 2. Service override (max 120). The same line passes.
/// 3. Wildcard override (`*:line_length_linter`). Same effect as scenario 2,
///    via the winner-scoped override syntax.
///
/// `DiagnosticCollectorPlugin` exposes a session-scoped collector so each
/// scenario can read the diagnostics published by [LinterSuitePlugin] in
/// response to [DocumentSavedEvent].
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/linter_suite.dart';
import 'package:plugin_kit/plugin_kit.dart';

// Document with one over-long line (exceeds 80, within 120).
final _doc = TextDocument(
  filename: 'widget.dart',
  content: 'class MyWidget {\n$dartLine85\n}',
  languageId: 'dart',
);

/// Session-scoped sink. Owns its own subscription via
/// `StatefulPluginService`, so `updateSessionSettings` reconciles it
/// correctly when the collector plugin is toggled.
class DiagnosticCollector extends SessionStatefulPluginService {
  final List<Diagnostic> diagnostics = [];

  @override
  void attach() {
    on<DiagnosticPublishedEvent>((event) {
      diagnostics.addAll(event.event.diagnostics);
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

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [LinterSuitePlugin(), DiagnosticCollectorPlugin()],
  )..init();

  // Scenario 1: default (max_line_length = 80).
  final session1 = await runtime.createSession();
  final diagnostics1 = await _runLinter(session1);
  print('Scenario 1: default (max 80):');
  _printDiagnostics(diagnostics1);
  await session1.dispose();

  // Scenario 2: scoped override (max_line_length = 120).
  final session2 = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin('linter_suite', ['line_length_linter']): ServiceSettings(
          config: {'max_line_length': 120},
        ),
      },
    ),
  );
  final diagnostics2 = await _runLinter(session2);
  print('Scenario 2: custom config (max 120):');
  _printDiagnostics(diagnostics2);
  await session2.dispose();

  // Scenario 3: wildcard override. `*:line_length_linter` targets whichever
  // plugin wins the `line_length_linter` slot. Same result as scenario 2.
  final session3 = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin.wildcard(['line_length_linter']): ServiceSettings(
          config: {'max_line_length': 120},
        ),
      },
    ),
  );
  final diagnostics3 = await _runLinter(session3);
  print('Scenario 3: wildcard *:line_length_linter (max 120):');
  _printDiagnostics(diagnostics3);

  await runtime.dispose();
}

Future<List<Diagnostic>> _runLinter(PluginSession session) async {
  final doc = TextDocument(
    filename: _doc.filename,
    content: _doc.content,
    languageId: _doc.languageId,
  );

  await session.emit(DocumentSavedEvent(doc));

  final collector = session.registry.resolve<DiagnosticCollector>(
    const ServiceId('diagnostic_collector'),
  );
  return [...collector.diagnostics];
}

void _printDiagnostics(List<Diagnostic> diagnostics) {
  if (diagnostics.isEmpty) {
    print('  (no diagnostics)');
  } else {
    for (final d in diagnostics) {
      print(d);
    }
  }
  print('');
}
