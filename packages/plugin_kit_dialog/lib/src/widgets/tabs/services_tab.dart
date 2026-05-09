import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../../plugin_kit_dialog.dart';
import '../../theme/plugin_kit_dialog_tokens.dart';
import '../services/namespace_section_card.dart';
import '../services/service_card.dart';

/// Immutable row model used to render one [ServiceCard] in [ServicesTab].
class ServiceEntry {
  /// Plugin id that owns this service registration.
  final PluginId pluginId;

  /// Service id in the registry (for example `agent.model` or `settings`).
  final ServiceId serviceId;

  /// Top-level namespace of [serviceId] when present, else null. Derived
  /// from `serviceId` at collection time so the tab can group by namespace.
  final Namespace? namespace;

  /// Winning registration priority for this service.
  final int priority;

  /// Configurable capabilities attached to this service.
  final List<UiConfigurableCapability> capabilities;

  /// Service-axis visual override (label/icon/color), or null.
  final PluginKitVisual? serviceVisual;

  /// Namespace-axis visual override for [namespace], or null when the
  /// service is unnamespaced or no namespace visual is registered.
  final PluginKitVisual? namespaceVisual;

  /// Plugin-axis visual override for [pluginId], or null.
  final PluginKitVisual? pluginVisual;

  /// Creates one service entry for [ServicesTab].
  const ServiceEntry({
    required this.pluginId,
    required this.serviceId,
    required this.namespace,
    required this.priority,
    required this.capabilities,
    this.serviceVisual,
    this.namespaceVisual,
    this.pluginVisual,
  });
}

/// Services tab body that renders one expandable [ServiceCard] per entry,
/// grouping namespaced services under a [NamespaceSectionCard].
class ServicesTab extends StatefulWidget {
  /// Dialog controller used by nested field sections.
  final PluginKitDialogController controller;

  /// Entries collected from target runtime service registrations.
  final List<ServiceEntry> entries;

  /// Resolves the field renderer for each [ConfigField].
  final FieldRenderResolver resolveRenderer;

  /// Creates a services tab bound to [controller] and [entries].
  const ServicesTab({
    super.key,
    required this.controller,
    required this.entries,
    required this.resolveRenderer,
  });

  @override
  State<ServicesTab> createState() => _ServicesTabState();
}

class _ServicesTabState extends State<ServicesTab> {
  final Set<Pin> _expandedKeys = <Pin>{};
  final Set<Namespace> _expandedNamespaces = <Namespace>{};

  @override
  void initState() {
    super.initState();
    // Default: all namespaces expanded so first paint matches today.
    for (final entry in widget.entries) {
      final ns = entry.namespace;
      if (ns != null) {
        _expandedNamespaces.add(ns);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _group(widget.entries);

    return ListView.separated(
      padding: kCardPadding,
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final group = groups[index];
        final groupNs = group.namespace;
        if (groupNs == null) {
          // Root services render as flat cards (existing behavior).
          return _ServiceEntryCard(
            entry: group.entries.single,
            controller: widget.controller,
            resolveRenderer: widget.resolveRenderer,
            expandedKeys: _expandedKeys,
            onToggleExpanded: _toggleEntryExpansion,
          );
        }
        return NamespaceSectionCard(
          key: ValueKey('ns:${groupNs.value}'),
          namespace: groupNs,
          visual: group.entries.first.namespaceVisual,
          expanded: _expandedNamespaces.contains(groupNs),
          onToggleExpanded: () {
            setState(() {
              if (!_expandedNamespaces.add(groupNs)) {
                _expandedNamespaces.remove(groupNs);
              }
            });
          },
          children: [
            for (final entry in group.entries)
              _ServiceEntryCard(
                entry: entry,
                controller: widget.controller,
                resolveRenderer: widget.resolveRenderer,
                expandedKeys: _expandedKeys,
                onToggleExpanded: _toggleEntryExpansion,
              ),
          ],
        );
      },
    );
  }

  void _toggleEntryExpansion(Pin scopedKey) {
    setState(() {
      if (!_expandedKeys.add(scopedKey)) {
        _expandedKeys.remove(scopedKey);
      }
    });
  }

  /// Groups [entries] into root-only groups (one entry each) and one group
  /// per namespace, preserving sort order.
  static List<_EntryGroup> _group(List<ServiceEntry> entries) {
    final groups = <_EntryGroup>[];
    Namespace? currentNamespace;
    List<ServiceEntry>? currentList;
    var sawAnyEntry = false;

    for (final entry in entries) {
      final ns = entry.namespace;
      if (ns == null) {
        groups.add(_EntryGroup(namespace: null, entries: [entry]));
        currentNamespace = null;
        currentList = null;
        sawAnyEntry = true;
        continue;
      }
      if (!sawAnyEntry || ns != currentNamespace) {
        currentList = [];
        groups.add(_EntryGroup(namespace: ns, entries: currentList));
        currentNamespace = ns;
      }
      currentList!.add(entry);
      sawAnyEntry = true;
    }
    return groups;
  }
}

class _EntryGroup {
  final Namespace? namespace;
  final List<ServiceEntry> entries;
  const _EntryGroup({required this.namespace, required this.entries});
}

/// Wraps a [ServiceCard] for one [ServiceEntry] and threads the dialog's
/// shared expansion state through. Lifted out of [_ServicesTabState] so
/// the build path stays widget-tree-only without `Widget`-returning
/// helper methods.
class _ServiceEntryCard extends StatelessWidget {
  final ServiceEntry entry;
  final PluginKitDialogController controller;
  final FieldRenderResolver resolveRenderer;
  final Set<Pin> expandedKeys;
  final void Function(Pin scopedKey) onToggleExpanded;

  const _ServiceEntryCard({
    required this.entry,
    required this.controller,
    required this.resolveRenderer,
    required this.expandedKeys,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final scopedKey = entry.pluginId.service(entry.serviceId);
    return ServiceCard(
      key: ValueKey(scopedKey.wire),
      pluginId: entry.pluginId,
      serviceId: entry.serviceId,
      priority: entry.priority,
      capabilities: entry.capabilities,
      serviceVisual: entry.serviceVisual,
      namespaceVisual: entry.namespaceVisual,
      pluginVisual: entry.pluginVisual,
      controller: controller,
      resolveRenderer: resolveRenderer,
      expanded: expandedKeys.contains(scopedKey),
      onToggleExpanded: () => onToggleExpanded(scopedKey),
    );
  }
}
