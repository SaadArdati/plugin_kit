import 'package:code_editor/mocks.dart';
import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../contributions.dart';
import '../factories.dart';
import '../theme.dart';

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
    return Container(
      color: EditorColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Branch header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EditorColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.commit, size: 14, color: EditorColors.warning),
                const SizedBox(width: 6),
                Text(
                  branch,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: EditorColors.warning,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // File list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: files.length,
              itemBuilder: (context, i) {
                final file = files[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        file.status == 'M' ? Icons.edit : Icons.add,
                        size: 14,
                        color: file.status == 'M'
                            ? EditorColors.warning
                            : EditorColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file.path,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        '+${file.additions} -${file.deletions}',
                        style: TextStyle(
                          fontSize: 11,
                          color: EditorColors.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Commit button
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCommit,
                icon: const Icon(Icons.check, size: 16),
                label: Text(
                  'Commit ${files.length} file${files.length == 1 ? '' : 's'}',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: EditorColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
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
  static const _branch = 'main';

  var _committed = false;

  @override
  Widget build(BuildContext context) => _GitChangesPanel(
    branch: _branch,
    files: _committed ? const [] : gitMockChanges,
    onCommit: () async {
      _committed = true;
      await emit(const UIRefreshRequest());
    },
  );

  @override
  void attach() {
    on<CollectToolbarActions>((envelope) async {
      envelope.event.actions.add(
        ToolbarActionDescriptor(
          id: 'git_branch',
          label: _branch,
          iconCodePoint: Icons.commit.codePoint,
          colorValue: EditorColors.warning.toARGB32(),
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
      final fileCount = _committed ? 0 : gitMockChanges.length;
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

class GitPlugin extends SessionPlugin {
  @override
  PluginId get pluginId => const PluginId('git');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerSingleton<PanelWidgetFactory>(
      ServiceSlots.panel('changes'),
      () => _GitPanelFactory(),
    );
  }
}
