import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

void main() {
  test('UiConfigurableCapability is a Capability', () {
    const cap = UiConfigurableCapability(label: 'X', fields: []);
    expect(cap, isA<Capability>());
  });

  test('UiConfigurableCapability holds label, description, fields', () {
    const cap = UiConfigurableCapability(
      label: 'Model & Provider',
      description: 'Pick a model',
      fields: [TextConfigField(key: 'model', label: 'Model')],
    );
    expect(cap.label, 'Model & Provider');
    expect(cap.description, 'Pick a model');
    expect(cap.fields, hasLength(1));
  });

  test('PluginKitVisual carries icon and color independently', () {
    const visuals = PluginKitVisual(
      icon: Icon(Icons.psychology),
      color: Color(0xFF7C5CFF),
    );
    expect((visuals.icon as Icon).icon, Icons.psychology);
    expect(visuals.color, const Color(0xFF7C5CFF));
    // PluginKitVisual is intentionally NOT a Capability: it's the
    // registered service instance under the visual namespaces.
    expect(visuals, isNot(isA<Capability>()));
  });

  test('multiple capabilities can be attached to one service', () {
    final caps = <Capability>{
      const UiConfigurableCapability(label: 'A', fields: []),
      const UiConfigurableCapability(label: 'B', fields: []),
    };
    expect(caps.whereType<UiConfigurableCapability>(), hasLength(2));
  });
}
