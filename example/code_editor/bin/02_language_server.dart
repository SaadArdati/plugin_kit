/// # 02: Language Server
///
/// The event bus as a request/response channel.
///
/// Both [SqlLanguagePlugin] and [DartLanguagePlugin] register
/// `CompletionRequest -> CompletionResponse` handlers via stateful
/// services. Each handler inspects the document's `languageId` and
/// returns completions only when the language matches, or null to concede.
/// Consumers call `maybeRequest` so a no-answer outcome surfaces as a
/// plain `null` return, not an exception.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/plugins/dart_language.dart';
import 'package:code_editor/plugins/sql_language.dart';
import 'package:plugin_kit/plugin_kit.dart';

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [SqlLanguagePlugin(), DartLanguagePlugin()],
  )..init();
  final session = await runtime.createSession();

  final sqlDoc = TextDocument(
    filename: 'query.sql',
    content: 'select * from ',
    languageId: 'sql',
  );

  final sqlResponse = await session
      .maybeRequest<CompletionRequest, CompletionResponse>(
        CompletionRequest(document: sqlDoc, line: 0, column: 14),
      );

  print('SQL completions for "${sqlDoc.content.trim()}":');
  if (sqlResponse != null) {
    for (final item in sqlResponse.items) {
      print('  $item');
    }
  }

  print('');

  final dartDoc = TextDocument(
    filename: 'main.dart',
    content: 'class MyApp {',
    languageId: 'dart',
  );

  final dartResponse = await session
      .maybeRequest<CompletionRequest, CompletionResponse>(
        CompletionRequest(document: dartDoc, line: 0, column: 13),
      );

  print('Dart completions for "${dartDoc.content.trim()}":');
  if (dartResponse != null) {
    for (final item in dartResponse.items) {
      print('  $item');
    }
  }

  await runtime.dispose();
}
