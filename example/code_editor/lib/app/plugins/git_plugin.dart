import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';

class GitPlugin extends SessionPlugin {
  static const id = PluginId('git');

  @override
  PluginId get pluginId => id;

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('changes'),
      _GitPanelFactory.new,
      capabilities: const {
        UiConfigurableCapability(
          label: 'Git',
          description: 'Working-tree label and filtering.',
          fields: [
            TextConfigField(
              key: 'branch',
              label: 'Branch',
              helperText: 'Shown in the toolbar pill and panel header.',
              defaultValue: 'main',
            ),
            BoolConfigField(
              key: 'showStagedOnly',
              label: 'Show staged only',
              helperText:
                  'Hide modified files; show only those marked as added.',
              defaultValue: false,
            ),
          ],
        ),
      },
    );
  }
}

class _GitChangesPanel extends StatelessWidget {
  const _GitChangesPanel({
    required this.branch,
    required this.files,
    required this.onCommit,
  });

  final String branch;
  final List<GitMockFile> files;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace');
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.commit,
                  size: 14,
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  branch,
                  style: mono?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: files.isEmpty
                ? Center(
                    child: Text(
                      'No changes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final file = files[i];
                      final isModified = file.status == 'M';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 3,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isModified ? Icons.edit : Icons.add,
                              size: 13,
                              color: isModified
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.tertiary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(file.path, style: mono)),
                            Text(
                              '+${file.additions} -${file.deletions}',
                              style: mono?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onCommit,
                  icon: const Icon(Icons.check, size: 14),
                  label: Text(
                    'Commit ${files.length} file${files.length == 1 ? '' : 's'}',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GitPanelFactory extends SessionStatefulPluginService
    implements PanelWidgetFactory {
  var _committed = false;

  String get _branch => config.get<String>('branch') ?? 'main';
  bool get _showStagedOnly => config.get<bool>('showStagedOnly') ?? false;

  List<GitMockFile> get _visibleFiles {
    if (_committed) return const [];
    if (_showStagedOnly) {
      return gitMockChanges.where((f) => f.status == 'A').toList();
    }
    return gitMockChanges;
  }

  @override
  Widget build(BuildContext context) => _GitChangesPanel(
    branch: _branch,
    files: _visibleFiles,
    onCommit: () async {
      _committed = true;
      await emit(const UIRefreshRequest());
    },
  );

  @override
  void onSettingsInjected() {
    // Initial injection can run before attach() binds the context; emit only
    // when context is live.
    if (hasContext) emit(const UIRefreshRequest());
  }

  @override
  void attach() {
    on<CollectToolbarActions>((envelope) async {
      envelope.event.actions.add(
        ToolbarActionDescriptor(
          id: 'git_branch',
          label: _branch,
          iconCodePoint: Icons.commit.codePoint,
        ),
      );
    });

    on<CollectPanels>((envelope) async {
      envelope.event.panels.add(
        const PanelDescriptor(
          id: 'changes',
          title: 'Changes',
          position: PanelPosition.right,
        ),
      );
    });

    on<CollectStatusBarItems>((envelope) async {
      final fileCount = _visibleFiles.length;
      envelope.event.items.add(
        StatusBarDescriptor(
          id: 'git_branch',
          text: '$_branch${fileCount > 0 ? ' (+$fileCount)' : ''}',
          iconCodePoint: Icons.commit.codePoint,
        ),
      );
    });

    on<ToolbarActionTriggered>((event) async {
      if (event.event.actionId == 'git_branch') {
        await emit(const TogglePanelRequest('changes'));
      }
    });
  }
}
