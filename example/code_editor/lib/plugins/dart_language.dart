/// Dart language support: analyzer and completion provider.
///
/// Registers a [LanguageService] that counts class declarations, imports,
/// and function signatures, plus a request handler for completions.
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

class DartAnalyzer implements LanguageService {
  @override
  String get languageId => 'dart';

  @override
  List<Diagnostic> analyze(TextDocument document) {
    final lines = document.lines;
    var classCount = 0;
    var importCount = 0;
    var functionCount = 0;

    for (final line in lines) {
      final trimmed = line.trimLeft();
      if (RegExp(r'^(abstract\s+)?class\s+\w+').hasMatch(trimmed)) {
        classCount++;
      }
      if (RegExp(r'^import\s+').hasMatch(trimmed)) {
        importCount++;
      }
      // Function/method: return type or void/Future, followed by identifier and `(`
      if (RegExp(r'^(\w+[\w<>\[\]?]*\s+)+\w+\s*\(').hasMatch(trimmed) &&
          !trimmed.startsWith('if') &&
          !trimmed.startsWith('while') &&
          !trimmed.startsWith('for') &&
          !trimmed.startsWith('switch') &&
          !trimmed.startsWith('class') &&
          !trimmed.startsWith('return')) {
        functionCount++;
      }
    }

    return [
      Diagnostic(
        line: 0,
        severity: DiagnosticSeverity.info,
        message:
            'Dart structure: $classCount class(es), '
            '$importCount import(s), $functionCount function/method(s)',
        source: 'dart_analyzer',
      ),
    ];
  }
}

class DartLanguagePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('dart_language');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<DartAnalyzer>(
      const ServiceId('dart_analyzer'),
      () => DartAnalyzer(),
    );
    registry.registerSingleton<_DartCompletionHandler>(
      const ServiceId('completion_handler'),
      () => _DartCompletionHandler(),
    );
  }
}

class _DartCompletionHandler extends SessionStatefulPluginService {
  static const _keywords = [
    'import',
    'export',
    'class',
    'abstract',
    'void',
    'final',
    'var',
    'const',
    'return',
    'if',
    'else',
    'for',
    'while',
    'switch',
    'case',
    'Future',
    'async',
    'await',
  ];

  @override
  void attach() {
    onRequest<CompletionRequest, CompletionResponse>((request) async {
      final doc = request.event.document;
      if (doc.languageId != 'dart') return null;

      final items = _keywords
          .map(
            (kw) => CompletionItem(
              label: kw,
              insertText: kw,
              detail: 'Dart keyword',
            ),
          )
          .toList();

      return CompletionResponse(items);
    });
  }
}
