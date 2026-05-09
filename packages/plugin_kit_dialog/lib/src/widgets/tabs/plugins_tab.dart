import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../controller/plugin_kit_dialog_controller.dart';
import '../../runtime/plugins/plugin_kit_visuals_plugin.dart';
import '../../runtime/plugins/plugins_tab_plugin.dart';
import '../../theme/plugin_kit_dialog_theme.dart';
import '../../theme/plugin_kit_dialog_tokens.dart';
import '../plugins/plugin_section.dart';
import '../plugins/plugin_stat_card.dart';

/// Plugins tab body with KPI cards, plugin sections, and agent config card.
class PluginsTab extends StatefulWidget {
  /// Controller that owns the editable draft and the target runtime.
  final PluginKitDialogController controller;

  /// Dialog runtime's registry where `PluginsTabPlugin` registered the
  /// default [PluginChipsBuilder]. Distinct from `controller.runtime`'s
  /// registry, which belongs to the host runtime being edited.
  final ServiceRegistry registry;

  /// Creates a plugins tab bound to [controller].
  const PluginsTab({
    super.key,
    required this.controller,
    required this.registry,
  });

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(PluginChipModel chip) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return chip.label.toLowerCase().contains(q) ||
        chip.pluginId.value.toLowerCase().contains(q);
  }

  /// Partitions [chips] so locked entries come first, preserving the
  /// runtime's relative order within each partition.
  static List<PluginChipModel> _lockedFirst(List<PluginChipModel> chips) {
    final locked = <PluginChipModel>[];
    final rest = <PluginChipModel>[];
    for (final chip in chips) {
      (chip.locked ? locked : rest).add(chip);
    }
    return [...locked, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final theme = PluginKitDialogTheme.of(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final builder = widget.registry.maybeResolve<PluginChipsBuilder>(
          PluginsTabPlugin.chipsBuilderId,
        );
        if (builder == null) {
          return const Center(
            child: Text(
              'Nothing to see here! No PluginChipsBuilder found in the registry.',
            ),
          );
        }

        final groups = builder.build(
          widget.controller.runtime,
          widget.controller.draft.working,
        );

        final filteredStable = _lockedFirst(
          groups.stable.where(_matches).toList(growable: false),
        );
        final filteredExperimental = _lockedFirst(
          groups.experimental.where(_matches).toList(growable: false),
        );
        final hasResults =
            filteredStable.isNotEmpty || filteredExperimental.isNotEmpty;

        return SingleChildScrollView(
          padding: kCardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PluginStatCard(
                      icon: Icons.extension,
                      iconBackground: theme.statActiveBackground,
                      numerator: groups.enabledCount,
                      denominator: groups.all.length,
                      label: 'Active Plugins',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PluginStatCard(
                      icon: Icons.shield_outlined,
                      iconBackground: theme.statStableBackground,
                      numerator: groups.stableEnabledCount,
                      denominator: groups.stable.length,
                      label: 'Stable',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PluginStatCard(
                      icon: Icons.science_outlined,
                      iconBackground: theme.statExperimentalBackground,
                      numerator: groups.experimentalEnabledCount,
                      denominator: groups.experimental.length,
                      label: 'Experimental',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _PluginSearchField(
                controller: _searchController,
                pluginCount: groups.all.length,
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
              const SizedBox(height: 16),
              if (filteredStable.isNotEmpty) ...[
                PluginSection(
                  controller: widget.controller,
                  plugins: filteredStable,
                  title: 'Stable Plugins',
                  subtitle: 'Production-ready plugins for your playground',
                  icon: Icons.shield,
                  accent: theme.stableAccent,
                ),
                const SizedBox(height: 16),
              ],
              if (filteredExperimental.isNotEmpty)
                PluginSection(
                  controller: widget.controller,
                  plugins: filteredExperimental,
                  title: 'Experimental Plugins',
                  subtitle: 'Beta features that may change or have limitations',
                  icon: Icons.science,
                  accent: theme.experimentalAccent,
                ),
              if (!hasResults) _SearchEmptyState(query: _query),
            ],
          ),
        );
      },
    );
  }
}

class _PluginSearchField extends StatelessWidget {
  const _PluginSearchField({
    required this.controller,
    required this.pluginCount,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final int pluginCount;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          hintText: pluginCount == 1
              ? 'Search 1 plugin…'
              : 'Search $pluginCount plugins…',
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints.tightFor(
            width: 36,
            height: 36,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: onClear,
                  tooltip: 'Clear search',
                  splashRadius: 16,
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final colorScheme = materialTheme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: materialTheme.cardBorderRadius,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 32,
            color: colorScheme.onSurface.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 8),
          Text(
            'No plugins match "$query"',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
