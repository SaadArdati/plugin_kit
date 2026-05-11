/// Formatter pipeline split into a generic base plugin and two
/// language-specific plugins that declare `formatter_pipeline` as a
/// dependency. Each plugin registers its own priority-ordered
/// `FormatDocumentEvent` hook.
library;

import 'package:code_editor/code_editor.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'sql_language.dart';

/// Owns the base pipeline hooks on a stateful service so
/// `updateSessionSettings` cleanly detaches and re-attaches them on
/// enable/disable.
class _BasePipelineHook extends SessionStatefulPluginService {
  @override
  void attach() {
    // WhitespaceTrimmer, priority 0.
    on<FormatDocumentEvent>((envelope) async {
      final doc = envelope.event.document;
      doc.content = doc.lines.map((line) => line.trimRight()).join('\n');
    }, priority: 0);

    // TrailingNewlineEnforcer, priority 10.
    on<FormatDocumentEvent>((envelope) async {
      final doc = envelope.event.document;
      doc.content = '${doc.content.trimRight()}\n';
    }, priority: 10);
  }
}

/// Base pipeline: generic stages that apply to every document.
///
/// - Priority 0: strip trailing whitespace per line.
/// - Priority 10: enforce exactly one trailing newline.
class FormatterPipelinePlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('formatter_pipeline');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_BasePipelineHook>(
      const ServiceId('pipeline_hook'),
      () => _BasePipelineHook(),
    );
  }
}

class _SqlFormatterHook extends SessionStatefulPluginService {
  @override
  void attach() {
    on<FormatDocumentEvent>((envelope) async {
      final doc = envelope.event.document;
      if (doc.languageId != 'sql') return;

      final uppercased = uppercaseSqlKeywords(doc.content);
      final collapsed = uppercased
          .split('\n')
          .map((line) => line.replaceAll(RegExp(r'[ \t]{2,}'), ' '))
          .join('\n');
      doc.content = collapsed;
    }, priority: 5);
  }
}

/// SQL-specific stage. Depends on [FormatterPipelinePlugin].
///
/// Priority 5: for `.sql` documents, uppercase keywords and collapse runs of
/// two or more spaces/tabs inside each line down to a single space.
class SqlFormatterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('sql_formatter');

  @override
  Set<PluginId> get dependencies => {const PluginId('formatter_pipeline')};

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_SqlFormatterHook>(
      const ServiceId('sql_formatter_hook'),
      () => _SqlFormatterHook(),
    );
  }
}

class _DartFormatterHook extends SessionStatefulPluginService {
  @override
  void attach() {
    on<FormatDocumentEvent>((envelope) async {
      final doc = envelope.event.document;
      if (doc.languageId != 'dart') return;
      doc.content = _formatDart(doc.content);
    }, priority: 3);
  }
}

/// Dart-specific stage. Depends on [FormatterPipelinePlugin].
///
/// Priority 3: for `.dart` documents, re-indent by brace depth.
class DartFormatterPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('dart_formatter');

  @override
  Set<PluginId> get dependencies => {const PluginId('formatter_pipeline')};

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<_DartFormatterHook>(
      const ServiceId('dart_formatter_hook'),
      () => _DartFormatterHook(),
    );
  }
}

/// Re-indents Dart code using 2-space indentation based on brace/bracket
/// depth. Collapses runs of 3+ blank lines into 1. Adds blank line after
/// import blocks.
String _formatDart(String content) {
  final lines = content.split('\n');
  final output = <String>[];
  var depth = 0;
  var consecutiveBlanks = 0;
  var lastWasImport = false;

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();

    // Collapse runs of blank lines
    if (trimmed.isEmpty) {
      consecutiveBlanks++;
      if (consecutiveBlanks <= 1) output.add('');
      continue;
    }
    consecutiveBlanks = 0;

    // Add blank line after import block transitions
    final isImport =
        trimmed.startsWith('import ') || trimmed.startsWith('export ');
    if (lastWasImport &&
        !isImport &&
        output.isNotEmpty &&
        output.last.isNotEmpty) {
      output.add('');
    }
    lastWasImport = isImport;

    // Closing braces/brackets reduce depth BEFORE this line
    if (trimmed.startsWith('}') ||
        trimmed.startsWith(')') ||
        trimmed.startsWith(']')) {
      depth = (depth - 1).clamp(0, 100);
    }

    // Apply indentation
    final indent = '  ' * depth;
    output.add('$indent$trimmed');

    // Opening braces increase depth AFTER this line.
    // If line has a net opener at the end (like `{`), increase depth.
    if (trimmed.endsWith('{') || trimmed.endsWith('(')) {
      depth++;
    } else if (trimmed.endsWith('{,') || trimmed.endsWith('(,')) {
      depth++;
    }
    // Lines that both close and open, like `}) {`: depth stays the same
    // since we already decremented above and increment here.
    else if (trimmed.contains('{') &&
        !trimmed.endsWith('}') &&
        !trimmed.endsWith('},') &&
        !trimmed.endsWith(');') &&
        !trimmed.endsWith('};')) {
      // Line has an opener somewhere but doesn't end with closer
      if (_countChar(trimmed, '{') > _countChar(trimmed, '}')) {
        depth++;
      }
    }
  }

  return output.join('\n');
}

int _countChar(String s, String ch) {
  var count = 0;
  for (var i = 0; i < s.length; i++) {
    if (s[i] == ch) count++;
  }
  return count;
}
