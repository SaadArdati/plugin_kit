import 'package:flutter/material.dart';
import 'package:plugin_kit/plugin_kit.dart';

import '../../../runtime/plugins/default_field_renderers_plugin.dart';

/// Placeholder renderer used when an [ExtensionConfigField]'s `rendererKey`
/// has no registered renderer. Renders an inline diagnostic instead of
/// crashing the dialog.
final class MissingExtensionRenderer
    implements ConfigFieldRenderer<ConfigField> {
  /// Creates a placeholder renderer that diagnoses [rendererKey].
  const MissingExtensionRenderer(this.rendererKey);

  /// The unresolved extension renderer key reported in the placeholder UI.
  final String rendererKey;

  @override
  Widget build(
    BuildContext context,
    ConfigField field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  ) {
    return _MissingExtensionRendererWidget(
      fieldKey: field.key,
      rendererKey: rendererKey,
    );
  }
}

class _MissingExtensionRendererWidget extends StatelessWidget {
  const _MissingExtensionRendererWidget({
    required this.fieldKey,
    required this.rendererKey,
  });

  final String fieldKey;
  final String rendererKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x33FF6B6B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x66FF6B6B)),
      ),
      child: Text(
        'No renderer registered for extension key "$rendererKey" '
        '(field "$fieldKey").',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFFFFB4B4),
          height: 1.3,
        ),
      ),
    );
  }
}
