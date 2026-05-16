/// Flutter capstone: a modular code editor where every UI element beyond the
/// text area and tab bar is contributed by plugins via the event bus.
///
/// The shell knows ZERO specific plugins. It emits collection events, reads
/// the descriptors plugins append, resolves widget factories from the
/// ServiceRegistry, and renders.
///
/// Visual style: JetBrains "Islands Dark" inspired, but built from stock
/// Material widgets only — every color, text style, and shape comes from
/// `Theme.of(context)`. The single theme builder lives in `theme.dart`.
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
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

import 'contributions.dart';
import 'factories.dart';
import 'plugin_visuals.dart';
import 'plugins/ai_assist_plugin.dart';
import 'plugins/git_plugin.dart';
import 'plugins/minimap_plugin.dart';
import 'plugins/runner_plugin.dart';
import 'plugins/terminal_plugin.dart';
import 'theme.dart';

/// How long to wait after the last keystroke before emitting
/// [DocumentChangedEvent]. Keeps plugins from thrashing on every character.
const _documentChangeDebounce = Duration(milliseconds: 150);

/// Gap between island Cards (canvas shows through to give the "floating" feel).
const _islandGap = 4.0;

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

/// Ordered list of UI plugin ids — drives the chip row and the default
/// enabled-state map. Order is stable so chips don't reshuffle.
const _uiPluginIds = [
  RunnerPlugin.id,
  GitPlugin.id,
  TerminalPlugin.id,
  AiAssistPlugin.id,
  MinimapPlugin.id,
];

class EditorApp extends StatelessWidget {
  const EditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Code Editor',
      debugShowCheckedModeBanner: false,
      theme: editorTheme(),
      home: PluginRuntimeScope(
        plugins: [
          ..._uiPlugins(),
          ..._behaviorPlugins(),
          editorVisualsPlugin(),
        ],
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
  late final PluginRuntime _runtime;
  PluginSession? _session;
  EventSubscription? _refreshSub;
  bool _runtimeInitialized = false;

  late final List<TextDocument> _documents;
  late TabController _tabController;
  late TextEditingController _textController;
  int _activeIndex = 0;

  late final Map<PluginId, bool> _pluginEnabled;
  RuntimeSettings _settings = const RuntimeSettings();

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
    _pluginEnabled = {for (final id in _uiPluginIds) id: true};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_runtimeInitialized) return;
    _runtime = PluginRuntimeScope.of(context);
    _runtimeInitialized = true;
    unawaited(_createSession());
  }

  Future<void> _createSession() async {
    _settings = RuntimeSettings(
      plugins: {
        for (final e in _pluginEnabled.entries)
          e.key: PluginConfig(enabled: e.value),
      },
    );
    _session = await _runtime.createSession(settings: _settings);
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
    // The ambient PluginRuntimeScope owns the runtime and disposes it on
    // unmount; the runtime's own dispose path iterates and disposes its
    // sessions. Disposing the session here too would race the scope's
    // runtime.dispose iteration and double-detach the plugins.
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

  /// Queues a settings mutation that runs against the latest committed
  /// `_settings`. The mutator is invoked inside the serialized future so
  /// rapid toggles never compute `next` from a stale snapshot. Errors are
  /// swallowed at the tail so a single failed reconciliation doesn't poison
  /// the queue for subsequent toggles.
  Future<void> _queueSettingsMutation(
    RuntimeSettings Function(RuntimeSettings current) mutate,
  ) {
    final next = _togglePending
        .then((_) async {
          final session = _session;
          if (session == null) return;
          final newSettings = mutate(_settings);
          await _runtime.updateSessionSettings(
            session,
            newSettings: newSettings,
          );
          if (!mounted) return;
          setState(() => _settings = newSettings);
          await _collectUI();
        })
        .catchError((Object error, StackTrace stack) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'code_editor',
            ),
          );
        });
    _togglePending = next;
    return next;
  }

  Future<void> _onTogglePlugin(PluginId pluginId, bool enabled) async {
    setState(() => _pluginEnabled[pluginId] = enabled);
    await _queueSettingsMutation(
      (current) => current.copyWith(
        plugins: {
          ...current.plugins,
          pluginId: PluginConfig(enabled: enabled),
        },
      ),
    );
  }

  Future<void> _openSettingsDialog() async {
    final result = await showPluginKitDialog(
      context: context,
      runtime: _runtime,
      initialSettings: _settings,
      onSave: (next) async {
        await _queueSettingsMutation((_) => next);
      },
    );
    if (result != null && mounted) {
      setState(() {
        for (final id in _uiPluginIds) {
          // Preserve current state if the dialog didn't carry an entry —
          // avoids forcing an unspecified plugin "enabled" by default and
          // works correctly if a plugin later becomes locked or experimental.
          final returned = result.plugins[id]?.enabled;
          if (returned != null) _pluginEnabled[id] = returned;
        }
      });
    }
  }

  PluginKitVisual? _visualFor(PluginId id) => _runtime.globalRegistry
      .maybeResolve<PluginKitVisual>(PluginKitVisualsPlugin.visualFor(id));

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
      body: Column(
        children: [
          _ChipBar(
            pluginIds: _uiPluginIds,
            enabled: _pluginEnabled,
            visualFor: _visualFor,
            onToggle: _onTogglePlugin,
            onOpenSettings: _openSettingsDialog,
          ),
          _Toolbar(
            actions: _toolbarActions,
            activeDocFilename: _documents[_activeIndex].filename,
            onTrigger: (id) {
              _session?.bus.emit<ToolbarActionTriggered>(
                event: ToolbarActionTriggered(id),
              );
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _islandGap,
                0,
                _islandGap,
                _islandGap,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Card(
                            child: Column(
                              children: [
                                _DocTabs(
                                  controller: _tabController,
                                  documents: _documents,
                                ),
                                Expanded(child: _buildEditor(context)),
                              ],
                            ),
                          ),
                        ),
                        if (bottomPanels.isNotEmpty) ...[
                          const SizedBox(height: _islandGap),
                          _BottomPanelArea(
                            panels: bottomPanels,
                            activeIndex: _activeBottomTab.clamp(
                              0,
                              bottomPanels.length - 1,
                            ),
                            open: _bottomPanelOpen,
                            onSelect: (i) {
                              setState(() {
                                if (_activeBottomTab == i && _bottomPanelOpen) {
                                  _bottomPanelOpen = false;
                                } else {
                                  _activeBottomTab = i;
                                  _bottomPanelOpen = true;
                                }
                              });
                            },
                            onToggleOpen: () => setState(
                              () => _bottomPanelOpen = !_bottomPanelOpen,
                            ),
                            resolvePanel: _resolvePanel,
                          ),
                        ],
                      ],
                    ),
                  ),
                  for (final panel in visibleRight) ...[
                    const SizedBox(width: _islandGap),
                    _SidePanel(
                      panel: panel,
                      onClose: () =>
                          setState(() => _openPanelIds.remove(panel.id)),
                      resolvePanel: _resolvePanel,
                    ),
                  ],
                ],
              ),
            ),
          ),
          _StatusBar(
            languageId: _documents[_activeIndex].languageId,
            items: _statusBarItems,
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _textController,
      maxLines: null,
      expands: true,
      style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace'),
      cursorColor: theme.colorScheme.primary,
      decoration: const InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
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
    );
  }

  Widget _resolvePanel(PanelDescriptor panel) {
    final factory = _session?.context.maybeResolve<PanelWidgetFactory>(
      ServiceSlots.panel(panel.id),
    );
    return Builder(
      builder: (context) =>
          factory?.build(context) ??
          Center(
            child: Text(
              'No content',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
    );
  }
}

class _ChipBar extends StatelessWidget {
  const _ChipBar({
    required this.pluginIds,
    required this.enabled,
    required this.visualFor,
    required this.onToggle,
    required this.onOpenSettings,
  });

  final List<PluginId> pluginIds;
  final Map<PluginId, bool> enabled;
  final PluginKitVisual? Function(PluginId) visualFor;
  final void Function(PluginId id, bool enabled) onToggle;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final id in pluginIds)
                    _PluginChip(
                      id: id,
                      visual: visualFor(id),
                      selected: enabled[id] ?? true,
                      onSelected: (v) => onToggle(id, v),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Plugin settings',
              onPressed: onOpenSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _PluginChip extends StatelessWidget {
  const _PluginChip({
    required this.id,
    required this.visual,
    required this.selected,
    required this.onSelected,
  });

  final PluginId id;
  final PluginKitVisual? visual;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = visual?.label ?? id.toString();
    final icon = visual?.icon;
    final accent = visual?.color ?? Theme.of(context).colorScheme.primary;
    return FilterChip(
      label: Text(label),
      avatar: icon == null
          ? null
          : IconTheme(
              data: IconThemeData(
                size: 14,
                color: selected
                    ? Theme.of(context).colorScheme.onPrimary
                    : accent,
              ),
              child: icon,
            ),
      selected: selected,
      selectedColor: accent,
      onSelected: onSelected,
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.actions,
    required this.activeDocFilename,
    required this.onTrigger,
  });

  final List<ToolbarActionDescriptor> actions;
  final String activeDocFilename;
  final void Function(String id) onTrigger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TextButton.icon(
                  onPressed: () => onTrigger(action.id),
                  icon: Icon(
                    IconData(action.iconCodePoint, fontFamily: 'MaterialIcons'),
                    size: 14,
                    color: action.colorValue != null
                        ? Color(action.colorValue!)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(action.label),
                ),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                activeDocFilename,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocTabs extends StatelessWidget {
  const _DocTabs({required this.controller, required this.documents});

  final TabController controller;
  final List<TextDocument> documents;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [for (final doc in documents) Tab(text: doc.filename)],
      ),
    );
  }
}

class _BottomPanelArea extends StatelessWidget {
  const _BottomPanelArea({
    required this.panels,
    required this.activeIndex,
    required this.open,
    required this.onSelect,
    required this.onToggleOpen,
    required this.resolvePanel,
  });

  final List<PanelDescriptor> panels;
  final int activeIndex;
  final bool open;
  final void Function(int index) onSelect;
  final VoidCallback onToggleOpen;
  final Widget Function(PanelDescriptor panel) resolvePanel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: panels.length,
                    itemBuilder: (context, i) => _PanelTabButton(
                      title: panels[i].title,
                      active: i == activeIndex && open,
                      onTap: () => onSelect(i),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  ),
                  tooltip: open ? 'Collapse' : 'Expand',
                  onPressed: onToggleOpen,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          if (open)
            SizedBox(height: 220, child: resolvePanel(panels[activeIndex])),
        ],
      ),
    );
  }
}

class _PanelTabButton extends StatelessWidget {
  const _PanelTabButton({
    required this.title,
    required this.active,
    required this.onTap,
  });

  final String title;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: active ? theme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: active
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.panel,
    required this.onClose,
    required this.resolvePanel,
  });

  final PanelDescriptor panel;
  final VoidCallback onClose;
  final Widget Function(PanelDescriptor panel) resolvePanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = panel.preferredWidth ?? 280;
    final isNarrow = width < 200;
    return SizedBox(
      width: width,
      child: Card(
        child: Column(
          children: [
            if (!isNarrow)
              SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          panel.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Close ${panel.title}',
                        onPressed: onClose,
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            Expanded(child: resolvePanel(panel)),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.languageId, required this.items});

  final String languageId;
  final List<StatusBarDescriptor> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      key: const Key('editor-status-bar'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Text(languageId.toUpperCase(), style: textStyle),
          const SizedBox(width: 16),
          for (final item in items) ...[
            if (item.iconCodePoint != null) ...[
              Icon(
                IconData(item.iconCodePoint!, fontFamily: 'MaterialIcons'),
                size: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(item.text, style: textStyle),
            const SizedBox(width: 16),
          ],
          const Spacer(),
          Text('plugin_kit', style: textStyle),
        ],
      ),
    );
  }
}
