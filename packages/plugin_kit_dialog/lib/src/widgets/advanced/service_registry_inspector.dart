import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

import '../shared/plugin_kit_dialog_card.dart';

/// Stable 10-color palette used to give every plugin its own identity across
/// every pill, dot, and chip in the registry inspector. Stability matters:
/// if a plugin is purple here, it's purple everywhere in the dialog.
const List<Color> _pluginPalette = <Color>[
  Color(0xFFA78BFA), // purple
  Color(0xFF60A5FA), // blue
  Color(0xFF22C55E), // green
  Color(0xFFF59E0B), // amber
  Color(0xFFEC4899), // pink
  Color(0xFF0EA5E9), // sky
  Color(0xFF84CC16), // lime
  Color(0xFFD946EF), // fuchsia
  Color(0xFF14B8A6), // teal
  Color(0xFFF97316), // orange
];

/// Hash [pluginId] to a stable color from [_pluginPalette].
Color pluginColorFor(PluginId pluginId) {
  return _pluginPalette[pluginId.hashCode.abs() % _pluginPalette.length];
}

bool _isMetaNamespace(List<_ServiceClump> clumps) {
  for (final clump in clumps) {
    for (final reg in clump.registrations) {
      if (reg.pluginId != PluginKitVisualsPlugin.id) return false;
    }
  }
  return true;
}

/// Read-only registry inspector: each registered serviceId renders as one
/// collapsible row. Collapsed view shows the winner at a glance plus a dot
/// summary of every competing registration. Expanding reveals the full
/// priority chain with an amber crown and green `WINNER` badge on the
/// top-priority entry, dimmed rows for shadowed alternates, and a muted
/// dot for disabled-plugin registrations.
class ServiceRegistryInspector extends StatefulWidget {
  /// Runtime whose global registry is inspected by this widget.
  final PluginRuntime runtime;

  /// Controller used to resolve plugin enablement from working settings.
  final PluginKitDialogController controller;

  /// Creates a registry inspector bound to [runtime].
  const ServiceRegistryInspector({
    required this.runtime,
    required this.controller,
    super.key,
  });

  @override
  State<ServiceRegistryInspector> createState() =>
      _ServiceRegistryInspectorState();
}

class _ServiceRegistryInspectorState extends State<ServiceRegistryInspector> {
  String _filter = '';
  PluginId? _selectedPluginId;
  final Set<ServiceId> _expandedServiceIds = <ServiceId>{};

  /// Namespaces the user has explicitly toggled away from their default
  /// collapsed/expanded state. Meta namespaces are collapsed by default;
  /// non-meta are expanded; this set captures user overrides.
  ///
  /// Stays `Set<String>` because the grouping uses a `'root'` sentinel for
  /// unnamespaced services; introducing a typed sentinel would buy nothing
  /// at this leaf widget.
  final Set<String> _toggledNamespaces = <String>{};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final clumps = _collectClumps();
        final pluginIds = <PluginId>{
          for (final clump in clumps)
            for (final r in clump.registrations) r.pluginId,
        }.toList()..sort((a, b) => a.compareTo(b));
        final filteredClumps = _applyFilters(clumps);
        final grouped = _groupByNamespace(filteredClumps);
        final registrationCount = clumps.fold<int>(
          0,
          (count, clump) => count + clump.registrations.length,
        );

        return PluginKitDialogCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InspectorHeader(
                serviceCount: clumps.length,
                registrationCount: registrationCount,
                pluginCount: pluginIds.length,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: TextField(
                  onChanged: (value) => setState(() => _filter = value),
                  style: Theme.of(context).textTheme.bodySmall,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Filter services…',
                    prefixIcon: Icon(Icons.search, size: 16),
                    prefixIconConstraints: BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _PluginFilterChip(
                      label: 'All',
                      pluginId: null,
                      selected: _selectedPluginId == null,
                      onTap: () => setState(() => _selectedPluginId = null),
                    ),
                    for (final pluginId in pluginIds) ...[
                      const SizedBox(width: 6),
                      _PluginFilterChip(
                        label: pluginId,
                        pluginId: pluginId,
                        selected: _selectedPluginId == pluginId,
                        onTap: () =>
                            setState(() => _selectedPluginId = pluginId),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (grouped.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No registrations match the current filters.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.3),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in grouped.entries)
                      Builder(
                        builder: (_) {
                          final isMeta = _isMetaNamespace(entry.value);
                          final defaultCollapsed =
                              isMeta &&
                              _selectedPluginId != PluginKitVisualsPlugin.id;
                          final isToggled = _toggledNamespaces.contains(
                            entry.key,
                          );
                          final isCollapsed = isToggled
                              ? !defaultCollapsed
                              : defaultCollapsed;
                          return _NamespaceBlock(
                            namespace: entry.key,
                            clumps: entry.value,
                            isMeta: isMeta,
                            isCollapsed: isCollapsed,
                            onToggleCollapsed: () =>
                                _toggleNamespaceCollapsed(entry.key),
                            expanded: _expandedServiceIds,
                            onToggle: _toggleExpanded,
                          );
                        },
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  void _toggleExpanded(ServiceId serviceId) {
    setState(() {
      if (_expandedServiceIds.contains(serviceId)) {
        _expandedServiceIds.remove(serviceId);
      } else {
        _expandedServiceIds.add(serviceId);
      }
    });
  }

  void _toggleNamespaceCollapsed(String namespace) {
    setState(() {
      if (_toggledNamespaces.contains(namespace)) {
        _toggledNamespaces.remove(namespace);
      } else {
        _toggledNamespaces.add(namespace);
      }
    });
  }

  List<_ServiceClump> _collectClumps() {
    final registry = widget.runtime.globalRegistry;
    final pluginEnabledById = <PluginId, bool>{};

    final ids = registry.listAllServiceIds().toList()
      ..sort((a, b) => a.compareTo(b));
    final clumps = <_ServiceClump>[];
    for (final serviceId in ids) {
      final wrappers = registry.getRegistrations(serviceId);
      if (wrappers == null || wrappers.isEmpty) continue;

      final registrations = <_Registration>[];
      for (var index = 0; index < wrappers.length; index++) {
        final wrapper = wrappers[index];
        registrations.add(
          _Registration(
            serviceId: serviceId,
            pluginId: wrapper.pluginId,
            priority: wrapper.priority,
            isWinner: index == 0,
            pluginEnabled: pluginEnabledById.putIfAbsent(
              wrapper.pluginId,
              () => widget.runtime.isPluginEnabled(
                wrapper.pluginId,
                widget.controller.draft.working,
              ),
            ),
          ),
        );
      }
      clumps.add(
        _ServiceClump(serviceId: serviceId, registrations: registrations),
      );
    }
    return clumps;
  }

  List<_ServiceClump> _applyFilters(List<_ServiceClump> clumps) {
    final query = _filter.trim().toLowerCase();
    final filtered = <_ServiceClump>[];
    for (final clump in clumps) {
      final textMatches =
          query.isEmpty || clump.serviceId.toLowerCase().contains(query);
      if (!textMatches) continue;

      if (_selectedPluginId == null) {
        filtered.add(clump);
        continue;
      }
      final hasSelectedPlugin = clump.registrations.any(
        (r) => r.pluginId == _selectedPluginId,
      );
      if (hasSelectedPlugin) filtered.add(clump);
    }
    return filtered;
  }

  Map<String, List<_ServiceClump>> _groupByNamespace(
    List<_ServiceClump> clumps,
  ) {
    final grouped = <String, List<_ServiceClump>>{};
    for (final clump in clumps) {
      final String namespace = clump.serviceId.topNamespace ?? 'root';
      grouped.putIfAbsent(namespace, () => <_ServiceClump>[]).add(clump);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        final aMeta = _isMetaNamespace(grouped[a]!);
        final bMeta = _isMetaNamespace(grouped[b]!);
        if (aMeta != bMeta) return aMeta ? 1 : -1;
        return a.compareTo(b);
      });
    return {for (final key in keys) key: grouped[key]!};
  }
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({
    required this.serviceCount,
    required this.registrationCount,
    required this.pluginCount,
  });

  final int serviceCount;
  final int registrationCount;
  final int pluginCount;

  @override
  Widget build(BuildContext context) {
    final theme = PluginKitDialogTheme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = registrationCount == serviceCount
        ? '$serviceCount services · $pluginCount plugins'
        : '$serviceCount services · $registrationCount registrations · $pluginCount plugins';
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.agentAccent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.auto_awesome_mosaic,
            size: 16,
            color: theme.agentAccent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Service Registry',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NamespaceBlock extends StatelessWidget {
  const _NamespaceBlock({
    required this.namespace,
    required this.clumps,
    required this.isMeta,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.expanded,
    required this.onToggle,
  });

  final String namespace;
  final List<_ServiceClump> clumps;

  /// Namespace exists only to support the dialog's own visuals plumbing -
  /// every registration here is owned by `plugin_kit_visuals`. These get
  /// pushed down, collapsed by default, and rendered at reduced opacity so
  /// they don't drown out the host app's runtime plugins.
  final bool isMeta;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final Set<ServiceId> expanded;
  final void Function(ServiceId serviceId) onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final helperStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(height: 1.1);
    final isRoot = namespace == 'root';
    final block = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggleCollapsed,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4, left: 2),
              child: Row(
                children: [
                  Icon(
                    isCollapsed
                        ? Icons.keyboard_arrow_right_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    namespace.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      height: 1.2,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: isRoot
                          ? const Color(0xFFF97316)
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('·', style: helperStyle),
                  const SizedBox(width: 6),
                  Text('${clumps.length}', style: helperStyle),
                  if (isMeta) ...[const SizedBox(width: 8), const _MetaBadge()],
                ],
              ),
            ),
          ),
        ),
        if (!isCollapsed)
          for (final clump in clumps)
            _ServiceRow(
              clump: clump,
              isExpanded: expanded.contains(clump.serviceId),
              onToggle: () => onToggle(clump.serviceId),
            ),
      ],
    );
    if (isMeta) {
      return Opacity(opacity: 0.55, child: block);
    }
    return block;
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        'meta',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          height: 1.0,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.clump,
    required this.isExpanded,
    required this.onToggle,
  });

  final _ServiceClump clump;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final winner = clump.registrations.first;
    final hasCompetition = clump.registrations.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: isExpanded
              ? colorScheme.onSurface.withValues(alpha: 0.03)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: Row(
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '.${clump.serviceId}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.25,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PluginPill(
                    pluginId: winner.pluginId,
                    priority: winner.priority,
                    status: _statusFor(winner, isWinner: true),
                  ),
                  if (hasCompetition) ...[
                    const SizedBox(width: 8),
                    _PriorityDotSummary(registrations: clump.registrations),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (isExpanded) _PriorityChain(clump: clump),
      ],
    );
  }

  _RegStatus _statusFor(_Registration r, {required bool isWinner}) {
    if (!r.pluginEnabled) return _RegStatus.disabled;
    if (!isWinner) return _RegStatus.shadowed;
    return _RegStatus.winner;
  }
}

class _PriorityDotSummary extends StatelessWidget {
  const _PriorityDotSummary({required this.registrations});

  final List<_Registration> registrations;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < registrations.length; i++) ...[
          if (i != 0) const SizedBox(width: 3),
          _PriorityDot(registration: registrations[i], isWinner: i == 0),
        ],
      ],
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.registration, required this.isWinner});

  final _Registration registration;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final color = registration.pluginEnabled
        ? pluginColorFor(registration.pluginId)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final opacity = !registration.pluginEnabled
        ? 0.35
        : isWinner
        ? 1.0
        : 0.45;
    return Tooltip(
      message:
          '${registration.pluginId} · priority ${registration.priority}${isWinner ? ' · winner' : ''}',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _PriorityChain extends StatelessWidget {
  const _PriorityChain({required this.clump});

  final _ServiceClump clump;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 4, top: 2, bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
              width: 1.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < clump.registrations.length; i++)
              _PriorityChainEntry(
                registration: clump.registrations[i],
                isWinner: i == 0,
              ),
          ],
        ),
      ),
    );
  }
}

class _PriorityChainEntry extends StatelessWidget {
  const _PriorityChainEntry({
    required this.registration,
    required this.isWinner,
  });

  final _Registration registration;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = PluginKitDialogTheme.of(context);
    final pluginColor = pluginColorFor(registration.pluginId);
    final isDisabled = !registration.pluginEnabled;
    final rowOpacity = isDisabled
        ? 0.45
        : isWinner
        ? 1.0
        : 0.72;

    return Opacity(
      opacity: rowOpacity,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
        decoration: BoxDecoration(
          color: isWinner && !isDisabled
              ? pluginColor.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isWinner && !isDisabled
              ? Border.all(color: pluginColor.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          children: [
            if (isWinner)
              Icon(
                Icons.workspace_premium_rounded,
                size: 12,
                color: isDisabled
                    ? colorScheme.onSurfaceVariant
                    : theme.experimentalAccent,
              )
            else
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                registration.pluginId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: isWinner ? FontWeight.w600 : FontWeight.w400,
                  color: colorScheme.onSurface,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'p${registration.priority}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontFamily: 'monospace',
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 8),
            if (isWinner && !isDisabled)
              _WinnerBadge()
            else if (isDisabled)
              _StatusBadge(
                label: 'DISABLED',
                color: colorScheme.onSurfaceVariant,
              )
            else
              _StatusBadge(label: 'SHADOWED', color: theme.experimentalAccent),
            const SizedBox(width: 6),
            _StatusDot(
              key: ValueKey(
                'status-dot-${registration.pluginId}-${registration.serviceId}',
              ),
              status: isDisabled
                  ? _RegStatus.disabled
                  : (isWinner ? _RegStatus.winner : _RegStatus.shadowed),
            ),
          ],
        ),
      ),
    );
  }
}

class _WinnerBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final accent = PluginKitDialogTheme.of(context).stableAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Text(
        'WINNER',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: accent,
          height: 1.0,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
}

class _PluginPill extends StatelessWidget {
  const _PluginPill({
    required this.pluginId,
    required this.priority,
    required this.status,
  });

  final PluginId pluginId;
  final int priority;
  final _RegStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pluginColor = pluginColorFor(pluginId);
    final isDisabled = status == _RegStatus.disabled;
    final bgColor = isDisabled
        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : Color.alphaBlend(
            pluginColor.withValues(alpha: 0.28),
            colorScheme.surface,
          );
    final fgColor = isDisabled
        ? colorScheme.onSurface.withValues(alpha: 0.55)
        : colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDisabled
              ? colorScheme.outlineVariant
              : pluginColor.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pluginId,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: fgColor,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 10,
            color: fgColor.withValues(alpha: 0.25),
          ),
          const SizedBox(width: 6),
          Text(
            'p$priority',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              color: fgColor.withValues(alpha: 0.72),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PluginFilterChip extends StatelessWidget {
  const _PluginFilterChip({
    required this.label,
    required this.pluginId,
    required this.selected,
    required this.onTap,
  }) : super(key: null);

  /// Key used by widget tests to locate a chip by its label.
  static ValueKey<String> keyFor(String label) =>
      ValueKey<String>('plugin-filter-chip-$label');

  final String label;
  final PluginId? pluginId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = pluginId == null
        ? colorScheme.primary
        : pluginColorFor(pluginId!);
    return KeyedSubtree(
      key: keyFor(label),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.55)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontFamily: pluginId == null ? null : 'monospace',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({super.key, required this.status});

  final _RegStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = PluginKitDialogTheme.of(context);
    final color = switch (status) {
      _RegStatus.winner => theme.stableAccent,
      _RegStatus.shadowed => theme.experimentalAccent,
      _RegStatus.disabled => Theme.of(
        context,
      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
    };
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

enum _RegStatus { winner, shadowed, disabled }

class _Registration {
  const _Registration({
    required this.serviceId,
    required this.pluginId,
    required this.priority,
    required this.isWinner,
    required this.pluginEnabled,
  });

  final ServiceId serviceId;
  final PluginId pluginId;
  final int priority;
  final bool isWinner;
  final bool pluginEnabled;
}

class _ServiceClump {
  const _ServiceClump({required this.serviceId, required this.registrations});

  final ServiceId serviceId;
  final List<_Registration> registrations;
}
