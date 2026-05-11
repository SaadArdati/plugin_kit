/// Pure Dart descriptors and events for plugin UI contributions.
///
/// Plugins contribute UI by appending descriptors to mutable collection
/// events. The shell emits the event, plugins mutate it, and the shell
/// renders based on the collected descriptors. Factories for the actual
/// widgets are resolved separately from the ServiceRegistry.
library;

import 'package:plugin_kit/plugin_kit.dart';

/// Service-registry namespaces for plugin contributions.
abstract final class ServiceSlots {
  /// Namespace for `PanelWidgetFactory` registrations. Panel plugins
  /// register their factory under this namespace with their own service
  /// id (e.g. `'console'`, `'minimap'`). The shell resolves via
  /// `maybeResolveNamespace<PanelWidgetFactory>(ServiceSlots.panel, id)`.
  static const Namespace panel = Namespace('panel');
}

/// Where a panel is positioned in the editor layout.
enum PanelPosition { bottom, left, right }

/// Describes a toolbar button a plugin wants to contribute.
class ToolbarActionDescriptor {
  final String id;
  final String label;
  final int iconCodePoint;
  final int? colorValue;

  const ToolbarActionDescriptor({
    required this.id,
    required this.label,
    required this.iconCodePoint,
    this.colorValue,
  });
}

/// Describes a panel a plugin wants to contribute.
class PanelDescriptor {
  final String id;
  final String title;
  final PanelPosition position;
  final int? iconCodePoint;

  /// Whether the shell should open this panel automatically when the
  /// session starts. Defaults to false.
  final bool autoOpen;

  /// Preferred width in logical pixels for left/right panels. If null,
  /// the shell uses a default width. Ignored for bottom panels.
  final double? preferredWidth;

  const PanelDescriptor({
    required this.id,
    required this.title,
    required this.position,
    this.iconCodePoint,
    this.autoOpen = false,
    this.preferredWidth,
  });
}

/// Describes a status bar entry a plugin wants to contribute.
class StatusBarDescriptor {
  final String id;
  final String text;
  final int? iconCodePoint;

  const StatusBarDescriptor({
    required this.id,
    required this.text,
    this.iconCodePoint,
  });
}

/// Emitted by the shell to collect toolbar actions from all enabled plugins.
class CollectToolbarActions {
  final List<ToolbarActionDescriptor> actions = [];
}

/// Emitted by the shell to collect panels from all enabled plugins.
// #docregion contributions-collect-panels
class CollectPanels {
  final List<PanelDescriptor> panels = [];
}
// #enddocregion contributions-collect-panels

/// Emitted by the shell to collect status bar items from all enabled plugins.
class CollectStatusBarItems {
  final List<StatusBarDescriptor> items = [];
}

/// Emitted when the user taps a plugin-contributed toolbar button.
class ToolbarActionTriggered {
  final String actionId;
  const ToolbarActionTriggered(this.actionId);
}

/// Emitted by the shell when the user edits the document content (debounced).
class DocumentChangedEvent {
  final String filename;
  final String content;
  const DocumentChangedEvent({required this.filename, required this.content});
}

/// Request the active document from the shell. Used by plugins (e.g.,
/// terminal) that need to operate on the current editor content.
class GetActiveDocument {
  const GetActiveDocument();
}

/// Tells the shell to sync the text controller after a plugin modified
/// the active document's content (e.g., format via terminal command).
class SyncEditorRequest {
  const SyncEditorRequest();
}

/// Toggle a panel's visibility. The shell tracks open/closed state per
/// panel ID independently of plugin enablement.
class TogglePanelRequest {
  final String panelId;
  const TogglePanelRequest(this.panelId);
}

/// Emitted by a plugin when its panel content or status has changed
/// and the shell should re-collect and rebuild.
class UIRefreshRequest {
  const UIRefreshRequest();
}
