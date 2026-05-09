/// # 05: Workspace Sessions
///
/// Two sessions share one runtime but each owns its own event bus and
/// service registry.
///
/// [SqlLanguagePlugin], [DartLanguagePlugin], and [FormatterPipelinePlugin]
/// are registered once. Two sessions are created:
///
/// - Session A (SQL): formatting uppercases SQL keywords.
/// - Session B (Dart): the SQL step is guarded by `languageId == 'sql'`
///   and does nothing.
///
/// Bus isolation is verified by a small `SavedEventProbePlugin`. Each
/// session gets its own probe service, so a save emitted on session B
/// only flips session B's probe; session A's stays untouched.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/dart_language.dart';
import 'package:code_editor/plugins/formatter_pipeline.dart';
import 'package:code_editor/plugins/sql_language.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Per-session probe. Flips when a [DocumentSavedEvent] fires on its bus.
/// The service owns its own subscription via `StatefulPluginService`.
/// No plugin-level attach code is needed: the base `Plugin.attach` iterates
/// registered stateful services and attaches them automatically.
class SavedEventProbe extends SessionStatefulPluginService {
  var received = false;

  @override
  void attach() {
    on<DocumentSavedEvent>((event) {
      received = true;
    });
  }
}

class SavedEventProbePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('saved_event_probe');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<SavedEventProbe>(
      const ServiceId('saved_event_probe'),
      SavedEventProbe(),
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [
      SqlLanguagePlugin(),
      DartLanguagePlugin(),
      FormatterPipelinePlugin(),
      SavedEventProbePlugin(),
    ],
  )..init();

  final sessionA = await runtime.createSession();
  final sessionB = await runtime.createSession();

  final sqlDoc = TextDocument(
    filename: 'schema.sql',
    content: messySqlAccounts,
    languageId: 'sql',
  );

  print('Session A (SQL): before:');
  for (final line in sqlDoc.lines) {
    print('  |$line|');
  }

  await sessionA.emit(FormatDocumentEvent(sqlDoc));

  print('Session A (SQL): after:');
  for (final line in sqlDoc.lines) {
    print('  |$line|');
  }
  print('');

  final dartDoc = TextDocument(
    filename: 'service.dart',
    content: messyDartService,
    languageId: 'dart',
  );

  print('Session B (Dart): before:');
  for (final line in dartDoc.lines) {
    print('  |$line|');
  }

  await sessionB.emit(FormatDocumentEvent(dartDoc));

  print('Session B (Dart): after:');
  for (final line in dartDoc.lines) {
    print('  |$line|');
  }
  print('');

  // Isolation check: probe in session A must stay false when only session B
  // fires a save.
  final probeA = sessionA.registry.resolve<SavedEventProbe>(
    const ServiceId('saved_event_probe'),
  );
  final probeB = sessionB.registry.resolve<SavedEventProbe>(
    const ServiceId('saved_event_probe'),
  );

  await sessionB.emit(DocumentSavedEvent(dartDoc));

  if (probeA.received) {
    throw StateError(
      'Bus isolation broken: session A received session B event',
    );
  }
  if (!probeB.received) {
    throw StateError(
      'Bus isolation broken: session B did not receive its own save event',
    );
  }
  print(
    'Bus isolation check passed: session A received=${probeA.received}, '
    'session B received=${probeB.received}',
  );

  await runtime.dispose();
}
