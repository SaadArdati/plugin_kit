import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';
import 'package:plugin_kit_dialog/src/runtime/dialog_global_context.dart';
import 'package:plugin_kit_dialog/src/runtime/events.dart';

void main() {
  test('CollectTabsEvent collects in order', () {
    final ev = CollectTabsEvent();
    ev.tabs.add(
      TabDescriptor(
        id: 'a',
        label: 'A',
        icon: const Icon(Icons.abc),
        order: 100,
        builder: (_) => const SizedBox(),
      ),
    );
    ev.tabs.add(
      TabDescriptor(
        id: 'b',
        label: 'B',
        icon: const Icon(Icons.backpack),
        order: 50,
        builder: (_) => const SizedBox(),
      ),
    );
    ev.tabs.add(
      TabDescriptor(
        id: 'c',
        label: 'C',
        icon: const Icon(Icons.cabin),
        order: 300,
        builder: (_) => const SizedBox(),
      ),
    );

    expect(ev.tabs, hasLength(3));
    expect(ev.tabs.map((tab) => tab.id).toList(), ['a', 'b', 'c']);
  });

  test('DialogGlobalContext stores runtime edit state', () {
    final targetRuntime = PluginRuntime.empty();
    final controller = PluginKitDialogController(
      runtime: targetRuntime,
      initialSettings: RuntimeSettings.empty(),
    );

    FutureOr<void> onSave(RuntimeSettings settings) {}

    var canceled = false;
    final context = DialogGlobalContext(
      registry: ServiceRegistry(),
      bus: EventBus(),
      runtime: targetRuntime,
      controller: controller,
      onSave: onSave,
      onCancel: () => canceled = true,
    );

    expect(context.runtime, same(targetRuntime));
    expect(context.controller, same(controller));
    expect(context.onSave, same(onSave));

    context.onCancel();
    expect(canceled, isTrue);
  });
}
