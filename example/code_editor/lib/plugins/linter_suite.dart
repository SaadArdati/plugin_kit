/// Linter suite: TODO detector and line-length checker.
///
/// Subscribes to [DocumentSavedEvent] and runs both linters, emitting
/// a [DiagnosticPublishedEvent] with the collected results.
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

class TodoLinter implements LinterService {
  const TodoLinter();

  @override
  String get name => 'todo_linter';

  @override
  List<Diagnostic> lint(TextDocument document) {
    final diagnostics = <Diagnostic>[];
    final lines = document.lines;
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'//\s*TODO', caseSensitive: false).hasMatch(lines[i])) {
        diagnostics.add(
          Diagnostic(
            line: i + 1,
            severity: DiagnosticSeverity.warning,
            message: 'TODO comment found: ${lines[i].trim()}',
            source: 'todo_linter',
          ),
        );
      }
    }
    return diagnostics;
  }
}

class LineLengthLinter extends PluginService implements LinterService {
  LineLengthLinter();

  @override
  String get name => 'line_length_linter';

  int get maxLineLength => config.getInt('max_line_length') ?? 80;

  @override
  List<Diagnostic> lint(TextDocument document) {
    final diagnostics = <Diagnostic>[];
    final lines = document.lines;
    final max = maxLineLength;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].length > max) {
        diagnostics.add(
          Diagnostic(
            line: i + 1,
            severity: DiagnosticSeverity.info,
            message:
                'Line ${i + 1} exceeds $max characters (${lines[i].length})',
            source: 'line_length_linter',
          ),
        );
      }
    }
    return diagnostics;
  }
}

/// Runs the TodoLinter and LineLengthLinter on every `DocumentSavedEvent`
/// and emits the combined diagnostics.
///
/// Uses `on` (observer) rather than `hook` (interceptor). Linting is a
/// pure side-effect: we don't want to block or mutate the save, so an
/// observer is the right tool. The subscription lives on this service
/// so `updateSessionSettings` tears it down on disable and restores it
/// on enable.
class _LinterSaveHook extends SessionStatefulPluginService {
  @override
  void attach() {
    on<DocumentSavedEvent>((event) async {
      final doc = event.event.document;
      final todoLinter = resolve<TodoLinter>(const ServiceId('todo_linter'));
      final lineLengthLinter = resolve<LineLengthLinter>(
        const ServiceId('line_length_linter'),
      );

      final diagnostics = [
        ...todoLinter.lint(doc),
        ...lineLengthLinter.lint(doc),
      ];
      await emit(DiagnosticPublishedEvent(doc.filename, diagnostics));
    });
  }
}

class LinterSuitePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('linter_suite');

  @override
  void register(ScopedServiceRegistry registry) {
    // TodoLinter: no config, register as eager singleton.
    registry.registerSingleton<TodoLinter>(
      const ServiceId('todo_linter'),
      () => const TodoLinter(),
    );

    // LineLengthLinter: reads config, register as lazy singleton.
    registry.registerLazySingleton<LineLengthLinter>(
      const ServiceId('line_length_linter'),
      LineLengthLinter.new,
    );

    // Save-handler service. The plugin's inherited attach/detach drives
    // it, so the subscription is reconciled correctly on settings changes.
    registry.registerSingleton<_LinterSaveHook>(
      const ServiceId('save_hook'),
      () => _LinterSaveHook(),
    );
  }
}
