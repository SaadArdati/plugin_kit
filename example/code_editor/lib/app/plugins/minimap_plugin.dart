import 'package:code_editor/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';
import '../theme.dart';

class _MinimapPanel extends StatelessWidget {
  const _MinimapPanel({required this.lines});

  final List<String> lines;

  Color _lineColor(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return Colors.transparent;

    // Comments
    if (trimmed.startsWith('//') ||
        trimmed.startsWith('--') ||
        trimmed.startsWith('#')) {
      return EditorColors.syntaxComment;
    }
    // Imports/exports
    if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
      return EditorColors.syntaxImport;
    }
    // Class/enum/abstract declarations
    if (trimmed.startsWith('class ') ||
        trimmed.startsWith('abstract ') ||
        trimmed.startsWith('enum ') ||
        trimmed.startsWith('mixin ') ||
        trimmed.startsWith('extension ')) {
      return EditorColors.syntaxType;
    }
    // Function/method keywords
    if (trimmed.startsWith('void ') ||
        trimmed.startsWith('Future') ||
        trimmed.startsWith('Stream') ||
        trimmed.startsWith('@override')) {
      return EditorColors.syntaxFunction;
    }
    // Return/control flow
    if (trimmed.startsWith('return ') ||
        trimmed.startsWith('if ') ||
        trimmed.startsWith('for ') ||
        trimmed.startsWith('while ') ||
        trimmed.startsWith('switch ')) {
      return EditorColors.syntaxKeyword;
    }
    // Strings
    if (trimmed.contains("'") || trimmed.contains('"')) {
      return EditorColors.syntaxString;
    }
    // SQL keywords
    final firstWord = trimmed.split(RegExp(r'[\s(,]')).first.toUpperCase();
    if ({
      'SELECT',
      'FROM',
      'WHERE',
      'ORDER',
      'INSERT',
      'UPDATE',
      'DELETE',
      'CREATE',
      'DROP',
      'JOIN',
      'GROUP',
      'HAVING',
      'LIMIT',
      'SET',
      'LEFT',
      'RIGHT',
      'INNER',
      'VALUES',
      'INTO',
      'ALTER',
    }.contains(firstWord)) {
      return EditorColors.syntaxKeyword;
    }
    // Braces and structural
    if (trimmed == '{' ||
        trimmed == '}' ||
        trimmed == '});' ||
        trimmed == ');' ||
        trimmed == '],') {
      return EditorColors.syntaxBrace;
    }
    return EditorColors.syntaxDefault;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EditorColors.canvas,
      width: 64,
      child: CustomPaint(
        painter: _MinimapPainter(lines, _lineColor),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Custom painter for smooth minimap rendering. Avoids per-line widget overhead.
class _MinimapPainter extends CustomPainter {
  _MinimapPainter(this.lines, this.colorFn);

  final List<String> lines;
  final Color Function(String) colorFn;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;

    const lineHeight = 2.5;
    const gap = 0.5;
    const hPad = 6.0;
    final maxWidth = size.width - hPad * 2;

    for (var i = 0; i < lines.length; i++) {
      final y = i * (lineHeight + gap) + 4;
      if (y > size.height) break;

      final line = lines[i];
      final barWidth = (line.length * 0.6).clamp(0.0, maxWidth);
      if (barWidth < 1) continue;

      final paint = Paint()..color = colorFn(line);
      canvas.drawRRect(
        RRect.fromLTRBR(
          hPad,
          y,
          hPad + barWidth,
          y + lineHeight,
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      lines.length != old.lines.length || !identical(lines, old.lines);
}

class _MinimapPanelFactory extends SessionStatefulPluginService
    implements PanelWidgetFactory {
  var _lines = <String>[];

  @override
  Widget build(BuildContext context) => _MinimapPanel(lines: _lines);

  @override
  void attach() {
    on<CollectPanels>((envelope) async {
      envelope.event.panels.add(
        const PanelDescriptor(
          id: 'minimap',
          title: 'Minimap',
          position: PanelPosition.right,
          autoOpen: true,
          preferredWidth: 64,
        ),
      );
    });

    on<DocumentOpenedEvent>((event) async {
      _lines = event.event.document.lines;
      await emit(const UIRefreshRequest());
    });

    on<DocumentFocusedEvent>((event) async {
      _lines = event.event.document.lines;
      await emit(const UIRefreshRequest());
    });

    on<DocumentChangedEvent>((event) async {
      _lines = event.event.content.split('\n');
      await emit(const UIRefreshRequest());
    });
  }
}

class MinimapPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('minimap');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('minimap'),
      () => _MinimapPanelFactory(),
    );
  }
}
