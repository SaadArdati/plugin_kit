/// # 01: Hello Extension
///
/// The simplest plugin lifecycle: register, resolve, call.
///
/// [MarkdownLanguagePlugin] registers a [MarkdownAnalyzer] as a
/// [LanguageService] in the service registry. After creating a session,
/// the analyzer is resolved by its service ID and called directly.
///
/// Expected output: 3 headings, 2 links, 1 code block, matching the
/// sample document below.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/markdown_language.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  final runtime = PluginRuntime(plugins: [MarkdownLanguagePlugin()])..init();
  final session = await runtime.createSession();

  // Resolve the MarkdownAnalyzer service registered by the plugin.
  final analyzer = session.registry.resolve<MarkdownAnalyzer>(
    const ServiceId('markdown_analyzer'),
  );

  final doc = TextDocument(
    filename: 'README.md',
    content: sampleMarkdown,
    languageId: 'markdown',
  );

  final diagnostics = analyzer.analyze(doc);

  print('Analyzed: ${doc.filename}');
  print('Language: ${analyzer.languageId}');
  print('');
  print('Diagnostics:');
  for (final d in diagnostics) {
    print(d);
  }

  await runtime.dispose();
}
