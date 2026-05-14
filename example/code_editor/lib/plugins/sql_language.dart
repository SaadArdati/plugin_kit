/// SQL language support: analyzer, formatter, and completion provider.
///
/// Registers a [LanguageService] that counts statement types, a
/// [FormatterService] that uppercases keywords via word-boundary regex,
/// and a request handler for [CompletionRequest]/[CompletionResponse].
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

const _sqlKeywords = [
  'select',
  'from',
  'where',
  'insert',
  'into',
  'values',
  'update',
  'set',
  'delete',
  'create',
  'table',
  'drop',
  'alter',
  'join',
  'on',
  'and',
  'or',
  'not',
  'null',
  'order',
  'by',
  'group',
  'having',
  'limit',
  'as',
  'distinct',
  'between',
  'like',
  'in',
  'is',
  'case',
  'when',
  'then',
  'else',
  'end',
  'inner',
  'outer',
  'left',
  'right',
  'cross',
  'union',
  'all',
  'exists',
  'primary',
  'key',
  'foreign',
  'references',
  'index',
  'view',
  'begin',
  'commit',
  'rollback',
];

/// Uppercases SQL keywords in [content] using word-boundary regex.
String uppercaseSqlKeywords(String content) {
  var result = content;
  for (final keyword in _sqlKeywords) {
    final regex = RegExp(r'\b' + keyword + r'\b', caseSensitive: false);
    result = result.replaceAllMapped(regex, (m) => m[0]!.toUpperCase());
  }
  return result;
}

class SqlAnalyzer implements LanguageService {
  @override
  String get languageId => 'sql';

  @override
  List<Diagnostic> analyze(TextDocument document) {
    final content = document.content.toUpperCase();
    final selects = RegExp(r'\bSELECT\b').allMatches(content).length;
    final inserts = RegExp(r'\bINSERT\b').allMatches(content).length;
    final updates = RegExp(r'\bUPDATE\b').allMatches(content).length;
    final deletes = RegExp(r'\bDELETE\b').allMatches(content).length;

    return [
      Diagnostic(
        line: 0,
        severity: DiagnosticSeverity.info,
        message:
            'SQL statements: $selects SELECT, $inserts INSERT, '
            '$updates UPDATE, $deletes DELETE',
        source: 'sql_analyzer',
      ),
    ];
  }
}

class SqlFormatter implements FormatterService {
  @override
  String get name => 'sql_formatter';

  @override
  String format(TextDocument document) {
    return uppercaseSqlKeywords(document.content);
  }
}

/// The set of known keywords for quick membership testing.
final _sqlKeywordSet = _sqlKeywords.map((k) => k.toUpperCase()).toSet();

/// Checks the first token of each line (where SQL keywords appear) and flags
/// likely typos using Levenshtein edit distance. Only the leading word is
/// checked, which avoids false positives on column and table names that
/// happen to look like misspelled keywords.
class SqlKeywordLinter implements LinterService {
  const SqlKeywordLinter();

  @override
  String get name => 'sql_keyword_linter';

  @override
  List<Diagnostic> lint(TextDocument document) {
    if (document.languageId != 'sql') return [];

    final diagnostics = <Diagnostic>[];
    final lines = document.lines;

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.isEmpty) continue;

      // Extract the first word. That's where SQL keywords live.
      final match = RegExp(r'^(\w+)').firstMatch(trimmed);
      if (match == null) continue;
      final firstWord = match.group(1)!;
      final upper = firstWord.toUpperCase();

      // Skip if it IS a known keyword
      if (_sqlKeywordSet.contains(upper)) continue;
      // Skip pure numbers and very short tokens
      if (RegExp(r'^\d+$').hasMatch(firstWord)) continue;
      if (firstWord.length < 3) continue;

      // Check if this leading word is a near-miss for a SQL keyword
      final bestMatch = _closestKeyword(upper);
      if (bestMatch != null) {
        diagnostics.add(
          Diagnostic(
            line: i + 1,
            severity: DiagnosticSeverity.warning,
            message: 'Unknown token "$firstWord": did you mean $bestMatch?',
            source: name,
          ),
        );
      }
    }

    return diagnostics;
  }

  /// Returns the closest keyword if [word] is a likely typo, or null if
  /// it's probably a valid identifier.
  String? _closestKeyword(String word) {
    if (word.length < 3) return null;

    String? best;
    var bestDist = 999;

    for (final keyword in _sqlKeywordSet) {
      // Only compare keywords of similar length (within 4 chars)
      if ((keyword.length - word.length).abs() > 4) continue;

      final dist = _editDistance(word, keyword);
      // Threshold: up to 50% of the longer word's length, clamped to [1, 5]
      final maxLen = word.length > keyword.length
          ? word.length
          : keyword.length;
      final threshold = (maxLen * 0.5).ceil().clamp(1, 5);

      if (dist <= threshold && dist < bestDist && dist > 0) {
        bestDist = dist;
        best = keyword;
      }
    }

    return best;
  }

  /// Levenshtein edit distance.
  static int _editDistance(String a, String b) {
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return dp[m][n];
  }
}

class SqlLanguagePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('sql_language');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<SqlAnalyzer>(
      const ServiceId('sql_analyzer'),
      () => SqlAnalyzer(),
    );

    registry.registerSingleton<SqlFormatter>(
      const ServiceId('sql_formatter'),
      () => SqlFormatter(),
    );

    registry.registerSingleton<SqlKeywordLinter>(
      const ServiceId('sql_keyword_linter'),
      () => const SqlKeywordLinter(),
    );
    registry.registerSingleton<_SqlSaveHook>(
      const ServiceId('save_hook'),
      () => _SqlSaveHook(),
    );
    registry.registerSingleton<_SqlCompletionHandler>(
      const ServiceId('completion_handler'),
      () => _SqlCompletionHandler(),
    );
  }
}

class _SqlSaveHook extends SessionStatefulPluginService {
  @override
  void attach() {
    on<DocumentSavedEvent>((event) async {
      final doc = event.event.document;
      if (doc.languageId != 'sql') return;

      final linter = resolve<SqlKeywordLinter>(
        const ServiceId('sql_keyword_linter'),
      );
      final analyzer = resolve<SqlAnalyzer>(const ServiceId('sql_analyzer'));
      final diagnostics = [...linter.lint(doc), ...analyzer.analyze(doc)];
      await emit(DiagnosticPublishedEvent(doc.filename, diagnostics));
    });
  }
}

class _SqlCompletionHandler extends SessionStatefulPluginService {
  static const _items = [
    CompletionItem(
      label: 'SELECT',
      insertText: 'SELECT',
      detail: 'SQL keyword',
    ),
    CompletionItem(label: 'FROM', insertText: 'FROM', detail: 'SQL keyword'),
    CompletionItem(label: 'WHERE', insertText: 'WHERE', detail: 'SQL keyword'),
    CompletionItem(
      label: 'INSERT INTO',
      insertText: 'INSERT INTO',
      detail: 'SQL keyword',
    ),
    CompletionItem(
      label: 'UPDATE',
      insertText: 'UPDATE',
      detail: 'SQL keyword',
    ),
    CompletionItem(
      label: 'DELETE FROM',
      insertText: 'DELETE FROM',
      detail: 'SQL keyword',
    ),
    CompletionItem(label: 'JOIN', insertText: 'JOIN', detail: 'SQL keyword'),
    CompletionItem(
      label: 'ORDER BY',
      insertText: 'ORDER BY',
      detail: 'SQL keyword',
    ),
    CompletionItem(
      label: 'GROUP BY',
      insertText: 'GROUP BY',
      detail: 'SQL keyword',
    ),
    CompletionItem(label: 'LIMIT', insertText: 'LIMIT', detail: 'SQL keyword'),
  ];

  @override
  void attach() {
    onRequest<CompletionRequest, CompletionResponse>((request) async {
      final doc = request.event.document;
      if (doc.languageId != 'sql') return null;
      return const CompletionResponse(_items);
    });
  }
}
