/// Markdown language support: structural analyzer.
///
/// Registers a [LanguageService] that counts headings, links, and code
/// blocks in Markdown documents.
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

class MarkdownAnalyzer implements LanguageService {
  @override
  String get languageId => 'markdown';

  @override
  List<Diagnostic> analyze(TextDocument document) {
    final lines = document.lines;

    // Headings: lines starting with one or more `#` followed by a space.
    final headingCount = lines
        .where((line) => RegExp(r'^#{1,6} ').hasMatch(line))
        .length;

    // Links: [text](url) patterns.
    final linkCount = RegExp(
      r'\[.*?\]\(.*?\)',
    ).allMatches(document.content).length;

    // Code blocks: count triple-backtick delimiters, divide by 2.
    final fenceCount = RegExp(r'```').allMatches(document.content).length;
    final codeBlockCount = fenceCount ~/ 2;

    return [
      Diagnostic(
        line: 0,
        severity: DiagnosticSeverity.info,
        message:
            'Document has $headingCount heading(s), '
            '$linkCount link(s), $codeBlockCount code block(s)',
        source: 'markdown_analyzer',
      ),
    ];
  }
}

class MarkdownLanguagePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('markdown_language');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<MarkdownAnalyzer>(
      const ServiceId('markdown_analyzer'),
      MarkdownAnalyzer(),
    );
  }
}
