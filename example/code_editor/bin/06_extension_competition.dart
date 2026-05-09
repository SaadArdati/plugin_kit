/// # 06: Extension Competition
///
/// Service registry priority, `resolveAfter`, and settings-driven priority
/// override.
///
/// Two [FormatterService] implementations compete for the `sql_formatter`
/// slot:
///
/// - `SqlFormatter` from [SqlLanguagePlugin], priority 50 (plugin default).
/// - [SqlIndentFormatter] from [SqlIndentPlugin], priority 100. Uppercases
///   keywords and inserts newlines before major SQL clauses.
///
/// Three rounds: default resolution, `resolveAfter` to skip the winner,
/// then a session-level settings override that boosts the lower-priority
/// formatter to priority 200 and flips the winner.
library;

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/sql_language.dart';
import 'package:plugin_kit/plugin_kit.dart';

/// Uppercases SQL keywords and inserts a newline before each major clause.
class SqlIndentFormatter implements FormatterService {
  @override
  String get name => 'sql_indent_formatter';

  static const _clauses = [
    'FROM',
    'WHERE',
    'ORDER BY',
    'GROUP BY',
    'HAVING',
    'LIMIT',
    'LEFT JOIN',
    'RIGHT JOIN',
    'INNER JOIN',
    'OUTER JOIN',
    'JOIN',
  ];

  @override
  String format(TextDocument document) {
    var result = uppercaseSqlKeywords(document.content);
    for (final clause in _clauses) {
      result = result.replaceAll(
        RegExp(r'\s+' + clause, caseSensitive: false),
        '\n$clause',
      );
    }
    return result.trim();
  }
}

class SqlIndentPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('sql_indent');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<SqlIndentFormatter>(
      const ServiceId('sql_formatter'),
      SqlIndentFormatter(),
      priority: 100,
    );
  }
}

Future<void> main() async {
  final runtime = PluginRuntime(
    plugins: [
      SqlLanguagePlugin(), // sql_formatter at priority 50
      SqlIndentPlugin(), // sql_formatter at priority 100
    ],
  )..init();

  // Round 1: default resolution picks the higher priority (SqlIndentFormatter).
  final session1 = await runtime.createSession();

  final doc1 = TextDocument(
    filename: 'query.sql',
    content: sqlOneLiner,
    languageId: 'sql',
  );

  final winner = session1.registry.resolve<FormatterService>(
    const ServiceId('sql_formatter'),
  );
  print('Round 1: winner: ${winner.name}');
  print('  ${winner.format(doc1)}');
  print('');

  // Round 2: resolveAfter skips the winner and returns the next candidate.
  final fallback = session1.registry.resolveAfter<FormatterService>(
    pluginId: const PluginId('sql_indent'),
    serviceId: const ServiceId('sql_formatter'),
  );

  print('Round 2: resolveAfter sql_indent: ${fallback.name}');
  print('  ${fallback.format(doc1)}');
  print('');

  await session1.dispose();

  // Round 3: ServiceSettings.priority overrides a registration's priority
  // at session creation. Bumping sql_language:sql_formatter to 200 flips
  // the winner away from sql_indent.
  final session2 = await runtime.createSession(
    settings: RuntimeSettings(
      services: {
        Pin('sql_language', ['sql_formatter']): ServiceSettings(priority: 200),
      },
    ),
  );

  final rawWrapper = session2.registry.resolveRaw<FormatterService>(
    const ServiceId('sql_formatter'),
  );
  final overrideWinner = session2.registry.resolve<FormatterService>(
    const ServiceId('sql_formatter'),
  );

  print('Round 3: after priority override (200):');
  print('  plugin:  ${rawWrapper.pluginId}');
  print('  priority: ${rawWrapper.priority}');
  print('  name:    ${overrideWinner.name}');
  final doc2 = TextDocument(
    filename: 'query.sql',
    content: sqlOneLiner,
    languageId: 'sql',
  );
  print('  ${overrideWinner.format(doc2)}');

  await runtime.dispose();
}
