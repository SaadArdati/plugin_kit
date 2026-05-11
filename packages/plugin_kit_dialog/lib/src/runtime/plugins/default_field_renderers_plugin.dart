import 'package:flutter/widgets.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';

import '../../widgets/services/fields/bool_field_input.dart';
import '../../widgets/services/fields/dropdown_field_input.dart';
import '../../widgets/services/fields/group_field_input.dart';
import '../../widgets/services/fields/multiline_field_input.dart';
import '../../widgets/services/fields/number_field_input.dart';
import '../../widgets/services/fields/password_field_input.dart';
import '../../widgets/services/fields/text_field_input.dart';

/// Signature for functions that resolve a [ConfigField]'s renderer.
///
/// Always accepts the broad [ConfigField] type: resolvers dispatch on the
/// runtime subtype. Parameterizing this typedef would create a contravariance
/// trap when nested renderers (e.g. `GroupFieldInput`) forward the resolver
/// down to children of arbitrary types.
typedef FieldRenderResolver = ConfigFieldRenderer Function(ConfigField field);

/// Factory interface that builds a widget for a [ConfigField] subtype.
// #docregion default-field-renderers-plugin-config-field-renderer
abstract interface class ConfigFieldRenderer<T extends ConfigField> {
  /// Builds a field input widget for [field] using [handle].
  ///
  /// [resolveRenderer] resolves renderers for nested fields (for example group
  /// field children).
  Widget build(
    BuildContext context,
    T field,
    ConfigFieldHandle handle,
    FieldRenderResolver resolveRenderer,
  );
}
// #enddocregion default-field-renderers-plugin-config-field-renderer

/// Registers built-in field renderers used by the dialog runtime.
class FieldRenderersPlugin extends GlobalPlugin<DialogGlobalContext> {
  /// Namespace for all registered renderers, used by the dialog runtime to
  /// resolve renderers for built-in field types.
  static const Namespace namespace = Namespace('config_field_renderer');

  @override
  PluginId get pluginId => const PluginId('field_renderers');

  @override
  void register(ScopedServiceRegistry registry) {
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('text'),
      _TextFieldRenderer.new,
    );
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('multiline'),
      _MultilineFieldRenderer.new,
    );
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('password'),
      _PasswordFieldRenderer.new,
    );
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('number'),
      _NumberFieldRenderer.new,
    );
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('dropdown'),
      _DropdownFieldRenderer.new,
    );
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('bool'),
      _BoolFieldRenderer.new,
    );
    registry.registerFactory<ConfigFieldRenderer>(
      namespace('group'),
      _GroupFieldRenderer.new,
    );
  }
}

/// Bridges [TextConfigField] to [TextFieldInput].
final class _TextFieldRenderer implements ConfigFieldRenderer<TextConfigField> {
  const _TextFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) =>
      TextFieldInput(field: field, handle: handle);
}

/// Bridges [MultilineConfigField] to [MultilineFieldInput].
final class _MultilineFieldRenderer
    implements ConfigFieldRenderer<MultilineConfigField> {
  const _MultilineFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) =>
      MultilineFieldInput(field: field, handle: handle);
}

/// Bridges [PasswordConfigField] to [PasswordFieldInput].
final class _PasswordFieldRenderer
    implements ConfigFieldRenderer<PasswordConfigField> {
  const _PasswordFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) =>
      PasswordFieldInput(field: field, handle: handle);
}

/// Bridges [NumberConfigField] to [NumberFieldInput].
final class _NumberFieldRenderer
    implements ConfigFieldRenderer<NumberConfigField> {
  const _NumberFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) =>
      NumberFieldInput(field: field, handle: handle);
}

/// Bridges [DropdownConfigField] to [DropdownFieldInput].
final class _DropdownFieldRenderer
    implements ConfigFieldRenderer<DropdownConfigField<Object?>> {
  const _DropdownFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) =>
      DropdownFieldInput<Object?>(field: field, handle: handle);
}

/// Bridges [BoolConfigField] to [BoolFieldInput].
final class _BoolFieldRenderer implements ConfigFieldRenderer<BoolConfigField> {
  const _BoolFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) =>
      BoolFieldInput(field: field, handle: handle);
}

/// Bridges [GroupConfigField] to [GroupFieldInput].
final class _GroupFieldRenderer
    implements ConfigFieldRenderer<GroupConfigField> {
  const _GroupFieldRenderer();

  @override
  Widget build(context, field, handle, resolveRenderer) => GroupFieldInput(
    field: field,
    handle: handle,
    resolveRenderer: resolveRenderer,
  );
}
