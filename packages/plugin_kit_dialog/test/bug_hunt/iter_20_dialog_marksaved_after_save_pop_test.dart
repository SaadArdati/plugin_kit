// Regression test for ISSUE-20260518-1240-dialog-marksaved-skipped-after-save-pop.
//
// Bug shape: in the default showPluginKitDialog flow, the outer handleSave
// pops the route between `await widget.onSave(...)` and the `!mounted`
// check in the inner `_handleSave`. The `!mounted` short-circuit then
// skipped `widget.controller.markSaved()`, leaving controller.isDirty
// true after a successful save.
//
// Load-bearing timing (verified against pre-fix code):
// 1. Externally own the controller so we can assert on it post-unmount.
// 2. onSave holds itself pending via a Completer that the TEST controls.
// 3. Between the test triggering save and completing the Completer, the
//    test calls `_ToggleHost.hide()` and pumps. The pump runs the
//    setState, which removes PluginKitDialogBody from the tree. Now
//    `mounted == false`.
// 4. The test completes the Completer. _handleSave resumes from the await
//    with `mounted == false`.
// 5. Pre-fix: `if (!mounted) return;` is hit before markSaved() and the
//    `isDirty=false` assertion fails.
// 6. Post-fix: markSaved() runs before the mounted check; the assertion
//    passes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_kit/plugin_kit.dart';
import 'package:plugin_kit_dialog/plugin_kit_dialog.dart';

class _StubPlugin extends GlobalPlugin {
  @override
  PluginId get pluginId => const PluginId('sample_plugin');
}

class _ToggleHost extends StatefulWidget {
  const _ToggleHost({
    super.key,
    required this.controller,
    required this.runtime,
    required this.savePending,
  });
  final PluginKitDialogController controller;
  final PluginRuntime runtime;
  final Completer<void> savePending;

  @override
  State<_ToggleHost> createState() => _ToggleHostState();
}

class _ToggleHostState extends State<_ToggleHost> {
  bool show = true;

  void hide() => setState(() => show = false);

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return PluginKitDialogBody(
      controller: widget.controller,
      runtime: widget.runtime,
      // onSave parks on the test-controlled completer. The test unmounts
      // the body THEN completes the future, so _handleSave's `mounted`
      // check is guaranteed to see false on resume.
      onSave: (settings) async {
        await widget.savePending.future;
      },
      onCancel: () {},
    );
  }
}

void main() {
  testWidgets('controller.isDirty=false after save even when the body unmounts '
      'during a parked onSave (ISSUE-20260518-1240 regression)', (
    tester,
  ) async {
    // PluginKitDialogBody needs a realistic viewport; the default
    // 800x600 clips the header and causes TextField layout asserts.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final runtime = PluginRuntime()..addPlugin(_StubPlugin());
    runtime.init(settings: RuntimeSettings());
    addTearDown(runtime.dispose);

    final controller = PluginKitDialogController(
      runtime: runtime,
      initialSettings: RuntimeSettings(),
    );

    final savePending = Completer<void>();
    final hostKey = GlobalKey<_ToggleHostState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _ToggleHost(
            key: hostKey,
            controller: controller,
            runtime: runtime,
            savePending: savePending,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dirty the draft so Save becomes enabled.
    await tester.tap(find.text('sample_plugin'));
    await tester.pumpAndSettle();
    expect(controller.isDirty, isTrue, reason: 'sanity: draft was dirtied');

    // Trigger save. onSave parks on the completer; _handleSave is now
    // awaiting widget.onSave(...).
    await tester.tap(find.text('Save'));
    await tester.pump();

    // Unmount the body BEFORE letting onSave return. After this
    // pumpAndSettle, PluginKitDialogBody is no longer in the tree, so
    // its State.mounted is false.
    hostKey.currentState!.hide();
    await tester.pumpAndSettle();

    // Sanity: the body really is gone.
    expect(find.byType(PluginKitDialogBody), findsNothing);

    // Now release onSave. _handleSave resumes from the await with
    // mounted == false. Pre-fix: markSaved() is gated by the !mounted
    // check and is skipped. Post-fix: markSaved() runs first.
    savePending.complete();
    await tester.pumpAndSettle();

    // THE assertion.
    expect(
      controller.isDirty,
      isFalse,
      reason:
          'markSaved() must run before the mounted check; pre-fix '
          'this assertion fails because !mounted returns early',
    );
  });
}
