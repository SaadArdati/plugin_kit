# Package Issues (auto-tracked by loops)

Canonical issue ledger for both the doc-audit and bug-hunt loops. Each entry
is keyed by a stable slug (`ISSUE-<slug>`), not a timestamp, so rediscovering
a bug updates the existing entry instead of creating duplicates.

Statuses:

- `OPEN`     - bug is real and the failing test (if any) still fails today.
- `CLOSED`   - the failing test passes against current code; bug is resolved.
- `ORPHANED` - the failing test file no longer exists; the bug may have been
               fixed but cannot be auto-verified.

Run `bash scripts/bug-hunt-loop/triage.sh` to re-verify every entry against
current code; the orchestrator also re-verifies on each loop start.


## ISSUE-cached-service-settings-not-cleared-on-override-removal

- status: CLOSED
- discovered: iter 4
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/service_registry.dart`
- summary: Removing a service settings override leaves a cached singleton or lazy-singleton `PluginService` stuck with the old non-empty `settings` and `config` from the previous override.
- severity: HIGH

## ISSUE-config-node-returns-mutable-views

- status: CLOSED
- discovered: iter 2
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/config_node.dart`
- summary: ConfigNode.list() and ConfigNode.map() return live mutable views, so a caller can mutate the supposedly read-only config snapshot and change the stored settings in place.
- severity: MEDIUM

## ISSUE-dialog-save-barrier-dismiss

- status: OPEN
- discovered: iter 1
- last_verified: 2026-05-15
- source file: `packages/plugin_kit_dialog/lib/src/widgets/plugin_kit_dialog.dart:108-126`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:145`
- summary: While `PluginKitDialogController.isSaving` is true, system back is blocked but barrier taps still use the original `barrierDismissible` value and can dismiss the dialog.
- repro: Call `showPluginKitDialog` with `barrierDismissible: true`, trigger save so `isSaving` becomes true, then tap outside the dialog.
- severity: HIGH

## ISSUE-event-notifier-late-event-after-dispose

- status: CLOSED
- discovered: orphan (synthesized by triage)
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: test now passes; bug resolved
- summary: orphan reproducer for event-notifier-late-event-after-dispose; auto-filed by triage
- severity: MEDIUM

## ISSUE-global-attach-leaks-stateful-subscriptions

- status: OPEN
- discovered: iter 16
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart:368-374`
- doc reference: `README.md:93`
- summary: A failed global plugin `attach()` can leave `StatefulPluginService` subscriptions opened during `attach` alive because the rolled-back plugin is never detached.
- repro: Make a global plugin whose `attach()` opens a tracked service subscription and then throws, then dispose the runtime and observe the subscription is not cancelled through detach/unbind.
- severity: HIGH

## ISSUE-global-init-failed-attach-leaks-subscriptions

- status: OPEN
- discovered: iter 4
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_04_global-init-failed-attach-leaks-subscriptions_test.dart`
- summary: When a global plugin's `attach()` fails during `runtime.init()`, any attach-time subscriptions or bound `StatefulPluginService` context created before the throw remain live even though the plugin is rolled back out of the runtime.
- severity: HIGH
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_04_global-init-failed-attach-leaks-subscriptions_test.dart
00:00 +0: bug-hunt iter 4: global-init-failed-attach-leaks-subscriptions cancels attach-time service subscriptions when global init attach fails
```

## ISSUE-init-logandskip-retains-unknown-service-pin

- status: OPEN
- discovered: iter 11
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_11_init_logandskip_retains_unknown_service_pin_test.dart`
- summary: Under `UnknownReferencePolicy.logAndSkip`, `init()` keeps a plugin-scoped service pin whose service id was not registered instead of actually dropping it.
- severity: MEDIUM
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_11_init_logandskip_retains_unknown_service_pin_test.dart
00:00 +0: bug-hunt iter 11: init-logandskip-retains-unknown-service-pin drops unknown plugin-scoped service pins from settings and overrides under logAndSkip
```

## ISSUE-init-retains-dropped-unknown-settings

- status: OPEN
- discovered: iter 1
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_01_init_retains_dropped_unknown_settings_test.dart`
- summary: `PluginRuntime.init()` keeps unknown `RuntimeSettings` entries in `runtime.settings` under `UnknownReferencePolicy.logAndSkip` or `ignore`, even though those policies say the entries are dropped.
- severity: MEDIUM
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_01_init_retains_dropped_unknown_settings_test.dart
00:00 +0: bug-hunt iter 1: init-retains-dropped-unknown-settings removes unknown plugin settings entries after init under logAndSkip
```

## ISSUE-number-integer-text-rounds

- status: OPEN
- discovered: iter 11
- last_verified: 2026-05-15
- source file: `packages/plugin_kit_dialog/lib/src/widgets/services/fields/number_field_input.dart:167-169`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:79`
- summary: Integer text input rounds decimal values instead of stripping the fractional part.
- repro: Set `isInteger: true`, enter `1.6` in a number text field, and observe that the stored value becomes `2`.
- severity: MEDIUM

## ISSUE-number-style-slider-needs-bounds

- status: OPEN
- discovered: iter 11
- last_verified: 2026-05-15
- source file: `packages/plugin_kit_dialog/lib/src/widgets/services/fields/number_field_input.dart:33-40`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:77`
- summary: `NumberFieldStyle.slider` does not force slider mode when either `min` or `max` is null.
- repro: Create a `NumberConfigField` with `style: NumberFieldStyle.slider` and only one bound, then open the dialog and observe text input rendering.
- severity: MEDIUM

## ISSUE-plugin-session-scope-no-retry-after-missing-ambient-runtime

- status: CLOSED
- discovered: iter 7
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/flutter_plugin_kit/lib/src/session_scope.dart`
- summary: After `PluginSessionScope` auto-create initially fails because no ambient `PluginRuntimeScope` exists, reparenting the same state under a newly added `PluginRuntimeScope` never retries session creation and the scope stays stuck on the old error.
- severity: MEDIUM

## ISSUE-pluginruntime-constructor-duplicate-pluginid

- status: OPEN
- discovered: iter 19
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart:166-188`
- doc reference: `website/src/content/docs/reference/plugins-and-lifecycle.mdx:56`
- summary: `PluginRuntime({plugins})` seeds `_plugins` directly and can register duplicate `pluginId` values that `addPlugin` would reject.
- repro: Construct `PluginRuntime(plugins: [PluginA(pluginId: PluginId('dup')), PluginB(pluginId: PluginId('dup'))])` and observe both entries present without a duplicate-id error.
- severity: HIGH

## ISSUE-registry-copy-rebuilds-lazy-singleton

- status: CLOSED
- discovered: iter 5
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/service_registry.dart`
- summary: ServiceRegistry.copy() rebuilds an already-created lazy singleton in the snapshot instead of preserving the cached instance, so resolving the same service from the copied registry creates a second singleton and reruns factory side effects.
- severity: MEDIUM

## ISSUE-runtime-dispose-aborts-after-first-throwing-session

- status: OPEN
- discovered: orphan (synthesized by triage)
- last_verified: 2026-05-15
- failing test: `packages/plugin_kit/test/bug_hunt/iter_02_runtime_dispose_aborts_after_first_throwing_session_test.dart`
- summary: orphan reproducer for runtime-dispose-aborts-after-first-throwing-session; auto-filed by triage
- severity: MEDIUM

## ISSUE-runtime-reinit-after-dispose-crashes

- status: OPEN
- discovered: iter 6
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_06_runtime_reinit_after_dispose_crashes_test.dart`
- summary: A runtime cannot be initialized again after `dispose()` even though `PluginRuntime.init()` is documented and partially implemented to support re-initialization.
- severity: HIGH
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_06_runtime_reinit_after_dispose_crashes_test.dart
00:00 +0: bug-hunt iter 6: runtime-reinit-after-dispose-crashes allows init to run again after dispose
```

## ISSUE-runtime-settings-aliases-caller-owned-maps

- status: OPEN
- discovered: orphan (synthesized by triage)
- last_verified: 2026-05-15
- failing test: `packages/plugin_kit/test/bug_hunt/iter_13_runtime_settings_aliases_caller_owned_maps_test.dart`
- summary: orphan reproducer for runtime-settings-aliases-caller-owned-maps; auto-filed by triage
- severity: MEDIUM

## ISSUE-service-settings-alias-runtime-config

- status: CLOSED
- discovered: iter 7
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/plugin/service.dart`
- summary: Mutating a resolved service's `settings` map mutates the runtime-owned service override config because injected settings are stored and forwarded by reference instead of copied.
- severity: HIGH

## ISSUE-service-settings-copywith-cannot-clear-priority

- status: WONTFIX
- discovered: maintainer-rejected (Dart language limitation)
- last_verified: 2026-05-15
- closed_at: 2026-05-15
- closed_reason: This is a Dart language limitation, not a `ServiceSettings` bug. Optional named parameters cannot distinguish "argument omitted" from "argument passed as null". Use `ServiceSettings.withClearedPriority()` instead. Do NOT replace `copyWith` with a sentinel-based `Object? priority` overload.
- source file: `packages/plugin_kit/lib/src/settings.dart`
- summary: copyWith cannot clear ServiceSettings.priority by passing null (Dart-language limitation, not a bug). Use withClearedPriority().
- severity: NOTE

## ISSUE-session-listener-stale-old-session-event-after-swap

- status: OPEN
- discovered: bug-hunt-loop run 20260515 (orchestrator pipefail bug obscured the result)
- last_verified: 2026-05-15
- failing test: `packages/flutter_plugin_kit/test/bug_hunt/iter_05_session-listener-stale-old-session-event-after-swap_test.dart`
- summary: session-listener-stale-old-session-event-after-swap
- severity: see test for assertion detail

## ISSUE-update-session-settings-accepts-foreign-session

- status: OPEN
- discovered: iter 8
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_08_update_session_settings_accepts_foreign_session_test.dart`
- summary: PluginRuntime.updateSessionSettings accepts a PluginSession created by a different runtime and mutates that foreign session instead of rejecting it.
- severity: HIGH
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_08_update_session_settings_accepts_foreign_session_test.dart
00:00 +0: bug-hunt iter 8: update-session-settings-accepts-foreign-session rejects updateSessionSettings for a session owned by another runtime
```

## ISSUE-update-session-settings-notify-throw-partial-state

- status: OPEN
- discovered: bug-hunt-loop run 20260515 (orchestrator pipefail bug obscured the result)
- last_verified: 2026-05-15
- failing test: `packages/plugin_kit/test/bug_hunt/iter_13_update_session_settings_notify_throw_partial_state_test.dart`
- summary: update-session-settings-notify-throw-partial-state
- severity: see test for assertion detail

## ISSUE-update-settings-before-init-lateinit-crash

- status: OPEN
- discovered: iter 10
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_10_update_settings_before_init_lateinit_crash_test.dart`
- summary: Calling `PluginRuntime.updateSettings()` before `init()` crashes with a `LateInitializationError` instead of rejecting the call up front.
- severity: MEDIUM
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/runtime_routing_test.dart
00:00 +0: /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/runtime_routing_test.dart: Plugin routing init only processes GlobalPlugins
```

## ISSUE-update-settings-logandskip-retains-unknown-plugin-config

- status: OPEN
- discovered: iter 12
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_12_update_settings_logandskip_retains_unknown_plugin_config_test.dart`
- summary: PluginRuntime.updateSettings() under UnknownReferencePolicy.logAndSkip preserves unknown plugin overrides in runtime.settings even though that policy says those entries are dropped.
- severity: MEDIUM
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_12_update_settings_logandskip_retains_unknown_plugin_config_test.dart
00:00 +0: bug-hunt iter 12: update-settings-logandskip-retains-unknown-plugin-config drops unknown plugin ids from runtime settings after updateSettings under logAndSkip
```

## ISSUE-update-settings-rollback-best-effort

- status: OPEN
- discovered: iter 16
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart:1557-1612`
- doc reference: `README.md:96`
- summary: `updateSettings` rollback is best-effort, rollback failures are only logged, so full restoration of the prior snapshot is not guaranteed.
- repro: Trigger an `updateSettings` failure and force a rollback failure in global or session rollback, then observe severe rollback logs and the original exception rethrown.
- severity: HIGH

## ISSUE-update-settings-rollback-loses-custom-session-settings

- status: OPEN
- discovered: iter 3
- last_verified: 2026-05-15
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_03_update_settings_rollback_loses_custom_session_settings_test.dart`
- summary: A failed `PluginRuntime.updateSettings()` rolls sessions with custom per-session settings back to the runtime-wide snapshot instead of each session's own pre-update settings.
- severity: HIGH
- red excerpt:

```
Resolving dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (100.0.0 available)
  analyzer 10.0.1 (13.0.0 available)
  bloc 9.2.0 (9.2.1 available)
  flutter_riverpod 2.6.1 (3.3.1 available)
  get_it 8.3.0 (9.2.1 available)
  matcher 0.12.19 (0.12.20 available)
  meta 1.17.0 (1.18.2 available)
  riverpod 2.6.1 (3.2.1 available)
  test 1.30.0 (1.31.1 available)
  test_api 0.7.10 (0.7.12 available)
  test_core 0.6.16 (0.6.18 available)
  vector_math 2.2.0 (2.3.0 available)
  vm_service 15.1.0 (15.2.0 available)
Got dependencies in `/Users/saadardati/IdeaProjects/plugin_kit`!
13 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_03_update_settings_rollback_loses_custom_session_settings_test.dart
00:00 +0: bug-hunt iter 3: update-settings-rollback-loses-custom-session-settings restores each session to its own pre-update settings after rollback
```
