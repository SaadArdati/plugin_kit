/// Flutter capstone: a modular code editor where every UI element beyond the
/// text area and tab bar is contributed by plugins via the event bus.
///
/// The shell knows ZERO specific plugins. It emits collection events, reads
/// the descriptors plugins append, resolves widget factories from the
/// ServiceRegistry, and renders.
///
/// Visual style: JetBrains Islands Dark inspired. Dark canvas with floating
/// panel "islands," rounded corners, and blue accents.
///
/// Flutter integration shape: the runtime is owned by `PluginRuntimeScope`
/// at the top of the shell, and dispose is routed through
/// `disposeAndReport` so an async detach failure surfaces via
/// `FlutterError.reportError`. The session itself stays imperative because
/// the chip toggle path calls `runtime.updateSessionSettings` to reconfigure
/// the live session, which `PluginSessionScope` does not currently model.
/// For the listener-mixin / event-notifier patterns, see the recipes in
/// `example/state_garden/lib/src/integrations/`.
library;

import 'dart:async';

import 'package:code_editor/code_editor.dart';
import 'package:code_editor/mocks.dart';
import 'package:code_editor/plugins/dart_language.dart';
import 'package:code_editor/plugins/formatter_pipeline.dart';
import 'package:code_editor/plugins/linter_suite.dart';
import 'package:code_editor/plugins/markdown_language.dart';
import 'package:code_editor/plugins/sql_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_plugin_kit/flutter_plugin_kit.dart';
import 'package:plugin_kit/plugin_kit.dart';

import 'contributions.dart';
import 'factories.dart';
import 'plugins/ai_assist_plugin.dart';
import 'plugins/git_plugin.dart';
import 'plugins/minimap_plugin.dart';
import 'plugins/runner_plugin.dart';
import 'plugins/terminal_plugin.dart';
import 'theme.dart';

/// How long to wait after the last keystroke before emitting
/// [DocumentChangedEvent]. Keeps plugins from thrashing on every character.
const _documentChangeDebounce = Duration(milliseconds: 150);

/// UI plugins, exposed as chips so the user can toggle them at runtime.
List<Plugin> _uiPlugins() => [
  RunnerPlugin(),
  GitPlugin(),
  TerminalPlugin(),
  AiAssistPlugin(),
  MinimapPlugin(),
];

/// Headless behavior plugins. Always on; provide the analysis, formatting,
/// and linting that drive the editor's integrations.
List<Plugin> _behaviorPlugins() => [
  SqlLanguagePlugin(),
  DartLanguagePlugin(),
  MarkdownLanguagePlugin(),
  FormatterPipelinePlugin(),
  SqlFormatterPlugin(),
  DartFormatterPlugin(),
  LinterSuitePlugin(),
];

const _pluginLabels = {
  PluginId('runner'): 'Runner',
  PluginId('git'): 'Git',
  PluginId('terminal'): 'Terminal',
  PluginId('ai_assist'): 'AI Assist',
  PluginId('minimap'): 'Minimap',
};

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Code Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: EditorColors.canvas,
        colorSchemeSeed: EditorColors.accent,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: PluginRuntimeScope(
        plugins: [..._uiPlugins(), ..._behaviorPlugins()],
        child: const _EditorScreen(),
      ),
    );
  }
}

class _EditorScreen extends StatefulWidget {
  const _EditorScreen();
  @override
  State<_EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<_EditorScreen>
    with SingleTickerProviderStateMixin {
  late final PluginRuntimeManager _manager;
  PluginSession? _session;
  StreamSubscription? _refreshSub;
  bool _managerInitialized = false;

  late final List<TextDocument> _documents;
  late TabController _tabController;
  late TextEditingController _textController;
  int _activeIndex = 0;

  late final Map<PluginId, bool> _pluginEnabled;

  List<ToolbarActionDescriptor> _toolbarActions = [];
  List<PanelDescriptor> _panels = [];
  List<StatusBarDescriptor> _statusBarItems = [];

  final Set<String> _openPanelIds = {};
  bool _bottomPanelOpen = true;
  int _activeBottomTab = 0;
  Timer? _changeDebounce;

  /// Serializes plugin-toggle reconciliations. `updateSessionSettings` is
  /// async; back-to-back toggles must not overlap or the second one
  /// computes `old` against a session state that hasn't finished applying
  /// the first toggle, silently dropping the change.
  Future<void> _togglePending = Future.value();

  @override
  void initState() {
    super.initState();
    _documents = [initialSqlDocument(), initialDartDocument()];
    _tabController = TabController(length: _documents.length, vsync: this)
      ..addListener(_onTabChanged);
    _textController = TextEditingController(text: _documents[0].content);
    _pluginEnabled = {for (final id in _pluginLabels.keys) id: true};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_managerInitialized) return;
    // Manager is owned by the ambient PluginRuntimeScope; this state only
    // builds and disposes the session it needs (the toggle handler calls
    // updateSessionSettings, which requires imperative session ownership).
    _manager = PluginRuntimeScope.of(context);
    _managerInitialized = true;
    unawaited(_createSession());
  }

  Future<void> _createSession() async {
    final pluginConfigs = <PluginId, PluginConfig>{
      for (final e in _pluginEnabled.entries)
        e.key: PluginConfig(enabled: e.value),
    };

    _session = await _manager.createSession(
      settings: RuntimeSettings(plugins: pluginConfigs),
    );

    _registerShellHandlers();
    _subscribeToRefresh();
    _emitDocumentOpened();
    await _collectUI();
  }

  void _registerShellHandlers() {
    final session = _session;
    if (session == null) return;

    session.onRequestSync<GetActiveDocument, TextDocument>((req) {
      _documents[_activeIndex].content = _textController.text;
      return _documents[_activeIndex];
    });

    session.on<SyncEditorRequest>((_) {
      if (!mounted) return;
      setState(() => _textController.text = _documents[_activeIndex].content);
      _emitDocumentFocused();
    });

    session.on<TogglePanelRequest>((e) {
      if (!mounted) return;
      final id = e.event.panelId;
      setState(() {
        if (_openPanelIds.contains(id)) {
          _openPanelIds.remove(id);
        } else {
          _openPanelIds.add(id);
        }
      });
    });
  }

  void _subscribeToRefresh() {
    _refreshSub?.cancel();
    _refreshSub = _session?.on<UIRefreshRequest>((_) async {
      if (!mounted) return;
      await _collectUI();
    });
  }

  Future<void> _collectUI() async {
    final session = _session;
    if (session == null) return;

    final toolbar = CollectToolbarActions();
    await session.emit(toolbar);
    final panels = CollectPanels();
    await session.emit(panels);
    final status = CollectStatusBarItems();
    await session.emit(status);

    if (!mounted) return;
    setState(() {
      _toolbarActions = toolbar.actions;
      _panels = panels.panels;
      _statusBarItems = status.items;

      // Auto-open any panel that requested it via PanelDescriptor.autoOpen.
      for (final p in _panels) {
        if (p.autoOpen) _openPanelIds.add(p.id);
      }

      final bottomPanels = _panels
          .where((p) => p.position == PanelPosition.bottom)
          .toList();
      if (_activeBottomTab >= bottomPanels.length) {
        _activeBottomTab = bottomPanels.isEmpty ? 0 : bottomPanels.length - 1;
      }
    });
  }

  void _emitDocumentOpened() {
    _session?.emit(DocumentOpenedEvent(_documents[_activeIndex]));
  }

  void _emitDocumentFocused() {
    _session?.emit(DocumentFocusedEvent(_documents[_activeIndex]));
  }

  @override
  void dispose() {
    _changeDebounce?.cancel();
    _refreshSub?.cancel();
    _tabController.dispose();
    _textController.dispose();
    // The ambient PluginRuntimeScope owns the manager and disposes it on
    // unmount; the manager's own dispose path iterates and disposes its
    // sessions. Disposing the session here too would race the scope's
    // manager.dispose iteration and double-detach the plugins.
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    _documents[_activeIndex].content = _textController.text;
    _activeIndex = _tabController.index;
    _textController.text = _documents[_activeIndex].content;
    _emitDocumentFocused();
    _collectUI();
  }

  Future<void> _onTogglePlugin(PluginId pluginId, bool enabled) async {
    setState(() => _pluginEnabled[pluginId] = enabled);

    _togglePending = _togglePending.then((_) async {
      final session = _session;
      if (session == null) return;
      final next = RuntimeSettings(
        plugins: {
          for (final e in _pluginEnabled.entries)
            e.key: PluginConfig(enabled: e.value),
        },
      );
      await _manager.runtime.updateSessionSettings(session, newSettings: next);
      await _collectUI();
    });
    await _togglePending;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPanels = _panels
        .where((p) => p.position == PanelPosition.bottom)
        .toList();
    final rightPanels = _panels
        .where((p) => p.position == PanelPosition.right)
        .toList();
    final visibleRight = rightPanels
        .where((p) => _openPanelIds.contains(p.id))
        .toList();

    return Scaffold(
      backgroundColor: EditorColors.canvas,
      body: Column(
        children: [
          _buildChipBar(),
          _buildToolbar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(3, 0, 3, 3),
              child: Row(
                children: [
                  // Editor column
                  Expanded(
                    child: Column(
                      children: [
                        _buildDocumentTabs(),
                        Expanded(child: _buildEditor()),
                        // Bottom panels: tabs on TOP, content below
                        if (bottomPanels.isNotEmpty)
                          _buildBottomArea(bottomPanels),
                      ],
                    ),
                  ),

                  // Right panels (floating islands)
                  for (final panel in visibleRight) ...[
                    const SizedBox(width: 3),
                    _buildSidePanel(panel),
                  ],
                ],
              ),
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildChipBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: EditorColors.surface,
      child: Row(
        children: [
          const Text('Plugins', style: EditorTextStyles.label),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in _pluginEnabled.entries)
                  _PluginChip(
                    label: _pluginLabels[entry.key] ?? entry.key.toString(),
                    selected: entry.value,
                    onSelected: (v) => _onTogglePlugin(entry.key, v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: EditorColors.surface,
        border: Border(bottom: BorderSide(color: EditorColors.borderSubtle)),
      ),
      child: Row(
        children: [
          for (final action in _toolbarActions)
            _ToolbarButton(
              label: action.label,
              iconCodePoint: action.iconCodePoint,
              colorValue: action.colorValue,
              onPressed: () {
                _session?.bus.emit<ToolbarActionTriggered>(
                  event: ToolbarActionTriggered(action.id),
                );
              },
            ),

          const Spacer(),

          // Document badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: EditorColors.surfaceBright,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _documents[_activeIndex].filename,
              style: EditorTextStyles.label,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentTabs() {
    return Container(
      height: 34,
      color: EditorColors.surface,
      child: Row(
        children: [
          for (var i = 0; i < _documents.length; i++)
            _DocTab(
              filename: _documents[i].filename,
              isActive: _activeIndex == i,
              onTap: () {
                _tabController.animateTo(i);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      color: EditorColors.editorBg,
      child: TextField(
        controller: _textController,
        maxLines: null,
        expands: true,
        style: EditorTextStyles.mono13,
        cursorColor: EditorColors.accent,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        ),
        onChanged: (value) {
          _documents[_activeIndex].content = value;
          _changeDebounce?.cancel();
          _changeDebounce = Timer(_documentChangeDebounce, () {
            _session?.bus.emit<DocumentChangedEvent>(
              event: DocumentChangedEvent(
                filename: _documents[_activeIndex].filename,
                content: value,
              ),
            );
          });
        },
      ),
    );
  }

  /// Bottom panel area: tab bar on top, content below.
  Widget _buildBottomArea(List<PanelDescriptor> bottomPanels) {
    final safeIndex = _activeBottomTab.clamp(0, bottomPanels.length - 1);

    return Container(
      margin: const EdgeInsets.only(top: 3),
      decoration: EditorDecorations.panelBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar (on top).
          Container(
            height: 30,
            color: EditorColors.surfaceHigh,
            child: Row(
              children: [
                for (var i = 0; i < bottomPanels.length; i++)
                  _PanelTab(
                    title: bottomPanels[i].title,
                    isActive: i == safeIndex && _bottomPanelOpen,
                    onTap: () {
                      setState(() {
                        if (_activeBottomTab == i && _bottomPanelOpen) {
                          _bottomPanelOpen = false;
                        } else {
                          _activeBottomTab = i;
                          _bottomPanelOpen = true;
                        }
                      });
                    },
                  ),
                const Spacer(),
                _IconBtn(
                  icon: _bottomPanelOpen
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  tooltip: _bottomPanelOpen ? 'Collapse' : 'Expand',
                  onTap: () =>
                      setState(() => _bottomPanelOpen = !_bottomPanelOpen),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // Content
          if (_bottomPanelOpen)
            SizedBox(
              height: 200,
              child: _resolvePanel(bottomPanels[safeIndex]),
            ),
        ],
      ),
    );
  }

  Widget _buildSidePanel(PanelDescriptor panel) {
    final width = panel.preferredWidth ?? 280;
    final isNarrow = width < 200;

    return Container(
      width: width,
      decoration: EditorDecorations.panelBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (!isNarrow)
            Container(
              height: 30,
              padding: const EdgeInsets.only(left: 10),
              color: EditorColors.surfaceHigh,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      panel.title,
                      style: EditorTextStyles.panelTitle,
                    ),
                  ),
                  _IconBtn(
                    icon: Icons.close,
                    tooltip: 'Close ${panel.title}',
                    onTap: () => setState(() => _openPanelIds.remove(panel.id)),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          Expanded(child: _resolvePanel(panel)),
        ],
      ),
    );
  }

  Widget _resolvePanel(PanelDescriptor panel) {
    final factory = _session?.context.maybeResolve<PanelWidgetFactory>(
      ServiceSlots.panel(panel.id),
    );
    return factory?.build(context) ??
        const Center(
          child: Text(
            'No content',
            style: TextStyle(color: EditorColors.textMuted, fontSize: 12),
          ),
        );
  }

  Widget _buildStatusBar() {
    return Container(
      key: const Key('editor-status-bar'),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: EditorColors.accentMuted,
      child: Row(
        children: [
          Text(
            _documents[_activeIndex].languageId.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              color: EditorColors.textOnAccent,
            ),
          ),
          const SizedBox(width: 16),

          for (final item in _statusBarItems) ...[
            if (item.iconCodePoint != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  IconData(item.iconCodePoint!, fontFamily: 'MaterialIcons'),
                  size: 12,
                  color: EditorColors.textOnAccent.withValues(alpha: 0.7),
                ),
              ),
            Text(
              item.text,
              style: const TextStyle(
                fontSize: 11,
                color: EditorColors.textOnAccent,
              ),
            ),
            const SizedBox(width: 16),
          ],

          const Spacer(),
          Text(
            'plugin_kit',
            style: TextStyle(
              fontSize: 11,
              color: EditorColors.textOnAccent.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared small widgets used by the shell, themed consistently.

/// Plugin toggle chip.
class _PluginChip extends StatelessWidget {
  const _PluginChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onSelected(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? EditorColors.selectedChip
              : EditorColors.surfaceBright,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected
                ? EditorColors.textOnAccent
                : EditorColors.textSecondary,
            fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Toolbar button with hover state.
class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.label,
    required this.iconCodePoint,
    required this.onPressed,
    this.colorValue,
  });

  final String label;
  final int iconCodePoint;
  final int? colorValue;
  final VoidCallback onPressed;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.colorValue != null
        ? Color(widget.colorValue!)
        : EditorColors.textSecondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovering ? EditorColors.surfaceBright : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconData(widget.iconCodePoint, fontFamily: 'MaterialIcons'),
                size: 15,
                color: iconColor,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  color: _hovering
                      ? EditorColors.textPrimary
                      : EditorColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Document tab.
class _DocTab extends StatefulWidget {
  const _DocTab({
    required this.filename,
    required this.isActive,
    required this.onTap,
  });

  final String filename;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_DocTab> createState() => _DocTabState();
}

class _DocTabState extends State<_DocTab> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.isActive
                ? EditorColors.editorBg
                : _hovering
                ? EditorColors.surfaceBright
                : Colors.transparent,
            border: Border(
              bottom: widget.isActive
                  ? const BorderSide(color: EditorColors.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.filename,
            style: widget.isActive
                ? EditorTextStyles.tabActive
                : EditorTextStyles.tabInactive,
          ),
        ),
      ),
    );
  }
}

/// Bottom panel tab.
class _PanelTab extends StatefulWidget {
  const _PanelTab({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  final String title;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_PanelTab> createState() => _PanelTabState();
}

class _PanelTabState extends State<_PanelTab> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovering && !widget.isActive
                ? EditorColors.hoverOverlay
                : Colors.transparent,
            border: Border(
              bottom: widget.isActive
                  ? const BorderSide(color: EditorColors.accent, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Text(
            widget.title,
            style: widget.isActive
                ? EditorTextStyles.tabActive
                : EditorTextStyles.tabInactive,
          ),
        ),
      ),
    );
  }
}

/// Small icon button with hover + tooltip.
class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hovering ? EditorColors.hoverOverlay : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 14,
              color: EditorColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
