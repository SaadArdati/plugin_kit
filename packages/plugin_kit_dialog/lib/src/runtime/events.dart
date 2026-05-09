import 'package:flutter/widgets.dart';

/// Event used by plugins to contribute tab descriptors (Spec §7.4).
class CollectTabsEvent {
  /// Mutable tab list that listeners append to.
  final Set<TabDescriptor> tabs = {};
}

/// Descriptor for one dialog tab contributed through [CollectTabsEvent].
class TabDescriptor {
  /// Stable tab identifier such as `plugins` or `advanced`.
  final String id;

  /// Human-readable tab label.
  final String label;

  /// Icon displayed in the tab header.
  final Widget icon;

  /// Sort key used to order tabs.
  final int order;

  /// Builder that returns the tab body widget.
  final WidgetBuilder builder;

  /// Creates a tab descriptor entry.
  const TabDescriptor({
    required this.id,
    required this.label,
    required this.icon,
    required this.order,
    required this.builder,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TabDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          order == other.order;

  @override
  int get hashCode => Object.hash(id, label, order);
}
