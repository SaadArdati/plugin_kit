import '../capabilities.dart';
import 'config_field.dart';

/// Capability advertising that a service can be edited in the dialog.
///
/// Lives in `plugin_kit` (Dart-only) so non-Flutter plugins can declare
/// their configuration surface without a Flutter dependency. Visual concerns
/// (icon, accent color, label) are layered on by the Flutter host via
/// `PluginKitVisualsPlugin` (a `GlobalPlugin` from `plugin_kit_dialog`),
/// keyed by `PluginId` / `Namespace` / `ServiceId`. The dialog falls back
/// to a generic gear icon and the theme's primary color when no visual is
/// supplied.
///
/// For custom field renderers without a Flutter dependency at declaration
/// time, use [ExtensionConfigField] inside [fields] and register a
/// Flutter-side `ConfigFieldRenderer` for its `rendererKey`.
///
/// A service may attach multiple instances of this capability. Each becomes
/// its own sub-section under the service card.
// #docregion ui-configurable-capability-ui-configurable-capability
class UiConfigurableCapability extends Capability {
  /// Section title shown at the top of the rendered card or sub-section.
  final String label;

  /// Optional one-line description below the title.
  final String? description;

  /// Field schema rendered top-to-bottom in the card.
  final List<ConfigField> fields;

  /// Creates a capability instance that renders one configuration card.
  const UiConfigurableCapability({
    required this.label,
    required this.fields,
    this.description,
  });
}

// #enddocregion ui-configurable-capability-ui-configurable-capability
