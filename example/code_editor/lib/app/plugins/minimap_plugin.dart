import 'package:code_editor/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';

class MinimapPlugin extends SessionPlugin {
  static const id = PluginId('minimap');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('minimap'),
      _MinimapPanelFactory.new,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Minimap',
          description: 'Overview rendering options.',
          fields: [
            BoolConfigField(
              key: 'colorize',
              label: 'Syntax colors',
              helperText: 'Tint bars by detected token type.',
              defaultValue: true,
            ),
            NumberConfigField(
              key: 'lineHeight',
              label: 'Line height',
              helperText: 'Pixels per source line in the overview.',
              min: 1.5,
              max: 4.0,
              step: 0.5,
              defaultValue: 2.5,
            ),
          ],
        ),
      },
    );
  }
}

// Domain-specific syntax colors used only by the minimap painter. These are
// not theme tokens — they encode source-token semantics independent of any
// app palette and are kept inline as literals.
const _syntaxComment = Color(0xFF7A7E85);
const _syntaxKeyword = Color(0xFFCF8E6D);
const _syntaxString = Color(0xFF6AAB73);
const _syntaxType = Color(0xFF56A8F5);
const _syntaxFunction = Color(0xFF56B6C2);
const _syntaxImport = Color(0xFFC77DBB);
const _syntaxBrace = Color(0xFF4E5157);
const _syntaxDefault = Color(0xFF8C8F94);

class _MinimapPanel extends StatelessWidget {
  const _MinimapPanel({
    required this.lines,
    required this.colorize,
    required this.lineHeight,
  });

  final List<String> lines;
  final bool colorize;
  final double lineHeight;

  Color _lineColor(String line, Color fallback) {
    if (!colorize) return fallback;
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return Colors.transparent;

    if (trimmed.startsWith('//') ||
        trimmed.startsWith('--') ||
        trimmed.startsWith('#')) {
      return _syntaxComment;
    }
    if (trimmed.startsWith('import ') || trimmed.startsWith('export ')) {
      return _syntaxImport;
    }
    if (trimmed.startsWith('class ') ||
        trimmed.startsWith('abstract ') ||
        trimmed.startsWith('enum ') ||
        trimmed.startsWith('mixin ') ||
        trimmed.startsWith('extension ')) {
      return _syntaxType;
    }
    if (trimmed.startsWith('void ') ||
        trimmed.startsWith('Future') ||
        trimmed.startsWith('Stream') ||
        trimmed.startsWith('@override')) {
      return _syntaxFunction;
    }
    if (trimmed.startsWith('return ') ||
        trimmed.startsWith('if ') ||
        trimmed.startsWith('for ') ||
        trimmed.startsWith('while ') ||
        trimmed.startsWith('switch ')) {
      return _syntaxKeyword;
    }
    if (trimmed.contains("'") || trimmed.contains('"')) {
      return _syntaxString;
    }
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
      return _syntaxKeyword;
    }
    if (trimmed == '{' ||
        trimmed == '}' ||
        trimmed == '});' ||
        trimmed == ');' ||
        trimmed == '],') {
      return _syntaxBrace;
    }
    return _syntaxDefault;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = theme.colorScheme.onSurfaceVariant;
    return Container(
      color: theme.colorScheme.surface,
      width: 64,
      child: CustomPaint(
        painter: _MinimapPainter(
          lines: lines,
          lineHeight: lineHeight,
          colorFn: (line) => _lineColor(line, fallback),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Custom painter for smooth minimap rendering. Avoids per-line widget overhead.
class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.lines,
    required this.lineHeight,
    required this.colorFn,
  });

  final List<String> lines;
  final double lineHeight;
  final Color Function(String) colorFn;

  @override
  void paint(Canvas canvas, Size size) {
    if (lines.isEmpty) return;

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
      lineHeight != old.lineHeight ||
      lines.length != old.lines.length ||
      !identical(lines, old.lines);
}

class _MinimapPanelFactory extends SessionStatefulPluginService
    implements PanelWidgetFactory {
  var _lines = <String>[];

  bool get _colorize => config.get<bool>('colorize') ?? true;
  double get _lineHeight => (config.get<num>('lineHeight') ?? 2.5).toDouble();

  @override
  Widget build(BuildContext context) => _MinimapPanel(
    lines: _lines,
    colorize: _colorize,
    lineHeight: _lineHeight,
  );

  @override
  void onSettingsInjected() {
    // Initial injection can run before attach() binds the context; emit only
    // when context is live.
    if (hasContext) emit(const UIRefreshRequest());
  }

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
