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
- last_verified: 2026-05-17
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/service_registry.dart`
- summary: Removing a service settings override leaves a cached singleton or lazy-singleton `PluginService` stuck with the old non-empty `settings` and `config` from the previous override.
- severity: HIGH

## ISSUE-config-node-returns-mutable-views

- status: CLOSED
- discovered: iter 2
- last_verified: 2026-05-17
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/config_node.dart`
- summary: ConfigNode.list() and ConfigNode.map() return live mutable views, so a caller can mutate the supposedly read-only config snapshot and change the stored settings in place.
- severity: MEDIUM

## ISSUE-dialog-save-barrier-dismiss

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: verified-not-repro: PopScope canPop: false correctly blocks barrier-tap dismissal during save; regression test added in plugin_kit_dialog_body_test.dart
- discovered: iter 1
- last_verified: 2026-05-17
- source file: `packages/plugin_kit_dialog/lib/src/widgets/plugin_kit_dialog.dart:108-126`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:145`
- summary: While `PluginKitDialogController.isSaving` is true, system back is blocked but barrier taps still use the original `barrierDismissible` value and can dismiss the dialog.
- repro: Call `showPluginKitDialog` with `barrierDismissible: true`, trigger save so `isSaving` becomes true, then tap outside the dialog.
- severity: HIGH

## ISSUE-event-notifier-late-event-after-dispose

- status: CLOSED
- discovered: orphan (synthesized by triage)
- last_verified: 2026-05-17
- closed_at: 2026-05-15
- closed_reason: test now passes; bug resolved
- summary: orphan reproducer for event-notifier-late-event-after-dispose; auto-filed by triage
- severity: MEDIUM

## ISSUE-global-attach-leaks-stateful-subscriptions

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: verified-not-repro: init.dart:241-269 explicitly cancels every activeSubscription and activeBinding during the failed-attach unwind; existing coverage in failed_attach_cleanup_test.dart
- discovered: iter 16
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart:368-374`
- doc reference: `README.md:93`
- summary: A failed global plugin `attach()` can leave `StatefulPluginService` subscriptions opened during `attach` alive because the rolled-back plugin is never detached.
- repro: Make a global plugin whose `attach()` opens a tracked service subscription and then throws, then dispose the runtime and observe the subscription is not cancelled through detach/unbind.
- severity: HIGH

## ISSUE-global-init-failed-attach-leaks-subscriptions

- status: CLOSED
- discovered: iter 4
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: When a global plugin's `attach()` fails during `runtime.init()`, any attach-time subscriptions or bound `StatefulPluginService` context created before the throw remain live even though the plugin is rolled back out of the runtime.
- severity: HIGH

## ISSUE-init-logandskip-retains-unknown-service-pin

- status: CLOSED
- discovered: iter 11
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: Under `UnknownReferencePolicy.logAndSkip`, `init()` keeps a plugin-scoped service pin whose service id was not registered instead of actually dropping it.
- severity: MEDIUM

## ISSUE-init-retains-dropped-unknown-settings

- status: CLOSED
- discovered: iter 1
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: `PluginRuntime.init()` keeps unknown `RuntimeSettings` entries in `runtime.settings` under `UnknownReferencePolicy.logAndSkip` or `ignore`, even though those policies say the entries are dropped.
- severity: MEDIUM

## ISSUE-number-integer-text-rounds

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: _coerceForWrite + _handleTextChanged now truncate via .truncate() instead of rounding
- discovered: iter 11
- last_verified: 2026-05-17
- source file: `packages/plugin_kit_dialog/lib/src/widgets/services/fields/number_field_input.dart:167-169`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:79`
- summary: Integer text input rounds decimal values instead of stripping the fractional part.
- repro: Set `isInteger: true`, enter `1.6` in a number text field, and observe that the stored value becomes `2`.
- severity: MEDIUM

## ISSUE-number-style-slider-needs-bounds

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: NumberConfigField ctor asserts that style: slider requires both min and max
- discovered: iter 11
- last_verified: 2026-05-17
- source file: `packages/plugin_kit_dialog/lib/src/widgets/services/fields/number_field_input.dart:33-40`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:77`
- summary: `NumberFieldStyle.slider` does not force slider mode when either `min` or `max` is null.
- repro: Create a `NumberConfigField` with `style: NumberFieldStyle.slider` and only one bound, then open the dialog and observe text input rendering.
- severity: MEDIUM

## ISSUE-plugin-session-scope-no-retry-after-missing-ambient-runtime

- status: CLOSED
- discovered: iter 7
- last_verified: 2026-05-17
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/flutter_plugin_kit/lib/src/session_scope.dart`
- summary: After `PluginSessionScope` auto-create initially fails because no ambient `PluginRuntimeScope` exists, reparenting the same state under a newly added `PluginRuntimeScope` never retries session creation and the scope stays stuck on the old error.
- severity: MEDIUM

## ISSUE-pluginruntime-constructor-duplicate-pluginid

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: constructor now validates uniqueness and throws ArgumentError, matching addPlugin/addPlugins
- discovered: iter 19
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart:166-188`
- doc reference: `website/src/content/docs/reference/plugins-and-lifecycle.mdx:56`
- summary: `PluginRuntime({plugins})` seeds `_plugins` directly and can register duplicate `pluginId` values that `addPlugin` would reject.
- repro: Construct `PluginRuntime(plugins: [PluginA(pluginId: PluginId('dup')), PluginB(pluginId: PluginId('dup'))])` and observe both entries present without a duplicate-id error.
- severity: HIGH

## ISSUE-registry-copy-rebuilds-lazy-singleton

- status: CLOSED
- discovered: iter 5
- last_verified: 2026-05-17
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/service_registry.dart`
- summary: ServiceRegistry.copy() rebuilds an already-created lazy singleton in the snapshot instead of preserving the cached instance, so resolving the same service from the copied registry creates a second singleton and reruns factory side effects.
- severity: MEDIUM

## ISSUE-runtime-dispose-aborts-after-first-throwing-session

- status: CLOSED
- discovered: orphan (synthesized by triage)
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- summary: orphan reproducer for runtime-dispose-aborts-after-first-throwing-session; auto-filed by triage
- severity: MEDIUM

## ISSUE-runtime-reinit-after-dispose-crashes

- status: CLOSED
- discovered: iter 6
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: A runtime cannot be initialized again after `dispose()` even though `PluginRuntime.init()` is documented and partially implemented to support re-initialization.
- severity: HIGH

## ISSUE-runtime-settings-aliases-caller-owned-maps

- status: CLOSED
- discovered: orphan (synthesized by triage)
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- summary: orphan reproducer for runtime-settings-aliases-caller-owned-maps; auto-filed by triage
- severity: MEDIUM

## ISSUE-service-settings-alias-runtime-config

- status: CLOSED
- discovered: iter 7
- last_verified: 2026-05-17
- closed_at: 2026-05-15
- closed_reason: leaked codex fix verified working in earlier triage; test deleted; CLOSED state lost in subsequent triage run, restored manually
- source file: `packages/plugin_kit/lib/src/plugin/service.dart`
- summary: Mutating a resolved service's `settings` map mutates the runtime-owned service override config because injected settings are stored and forwarded by reference instead of copied.
- severity: HIGH

## ISSUE-service-settings-copywith-cannot-clear-priority

- status: WONTFIX
- discovered: maintainer-rejected (Dart language limitation)
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/settings.dart`
- summary: copyWith cannot clear ServiceSettings.priority by passing null (Dart-language limitation, not a bug). Use withClearedPriority().
- severity: NOTE

## ISSUE-session-listener-stale-old-session-event-after-swap

- status: CLOSED
- discovered: bug-hunt-loop run 20260515 (orchestrator pipefail bug obscured the result)
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- summary: session-listener-stale-old-session-event-after-swap
- severity: see test for assertion detail

## ISSUE-update-session-settings-accepts-foreign-session

- status: CLOSED
- discovered: iter 8
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: PluginRuntime.updateSessionSettings accepts a PluginSession created by a different runtime and mutates that foreign session instead of rejecting it.
- severity: HIGH

## ISSUE-update-session-settings-notify-throw-partial-state

- status: CLOSED
- discovered: bug-hunt-loop run 20260515 (orchestrator pipefail bug obscured the result)
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- summary: update-session-settings-notify-throw-partial-state
- severity: see test for assertion detail

## ISSUE-update-settings-before-init-lateinit-crash

- status: CLOSED
- discovered: iter 10
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: Calling `PluginRuntime.updateSettings()` before `init()` crashes with a `LateInitializationError` instead of rejecting the call up front.
- severity: MEDIUM

## ISSUE-update-settings-logandskip-retains-unknown-plugin-config

- status: CLOSED
- discovered: iter 12
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: PluginRuntime.updateSettings() under UnknownReferencePolicy.logAndSkip preserves unknown plugin overrides in runtime.settings even though that policy says those entries are dropped.
- severity: MEDIUM

## ISSUE-update-settings-rollback-best-effort

- status: WONTFIX
- closed_at: 2026-05-17
- closed_reason: best-effort rollback is intentional. There is no recovery if the rollback path itself throws (a plugin's re-attach during the rollback can't be retried automatically). Current behavior is: log severe with full context, rethrow the ORIGINAL exception so the caller sees the failed update they triggered. Adding a separate exception type (`PartialRollbackException`) was considered but adds API surface for a rare edge case where the caller can't usefully act differently. Documented as 'best-effort' on updateSettings dartdoc.
- discovered: iter 16
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart:1557-1612`
- doc reference: `README.md:96`
- summary: `updateSettings` rollback is best-effort, rollback failures are only logged, so full restoration of the prior snapshot is not guaranteed.
- repro: Trigger an `updateSettings` failure and force a rollback failure in global or session rollback, then observe severe rollback logs and the original exception rethrown.
- severity: HIGH

## ISSUE-update-settings-rollback-loses-custom-session-settings

- status: CLOSED
- discovered: iter 3
- last_verified: 2026-05-17
- closed_at: 2026-05-17
- closed_reason: test now passes; bug resolved
- source file: `packages/plugin_kit/lib/src/plugin/runtime.dart`
- summary: A failed `PluginRuntime.updateSettings()` rolls sessions with custom per-session settings back to the runtime-wide snapshot instead of each session's own pre-update settings.
- severity: HIGH
## ISSUE-settings-normalizer-shallow-copies-config-maps

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: defensive deep-copy of nested config maps added at every PluginConfig/ServiceSettings/RuntimeSettings IN/OUT boundary (ctor cannot, but copyWith/fromJson/toJson/normalizer/getters all do)
- discovered: iter 3
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/plugin/runtime/settings_normalizer.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_03_settings_normalizer_shallow_copies_config_maps_test.dart`
- summary: The runtime's settings normalizer shallow-copies only the outer maps, so mutating a caller-owned `PluginConfig.config` or `ServiceSettings.config` map after `init()` or `updateSettings()` silently mutates `runtime.settings`.
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
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_03_settings_normalizer_shallow_copies_config_maps_test.dart
00:00 +0: bug-hunt iter 3: settings-normalizer-shallow-copies-config-maps keeps runtime plugin config isolated from caller map mutations after init
```

## ISSUE-session-listener-detach-drops-cancel-future

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: detachSubscriptions now async and awaits Future.wait of every sub.cancel(); old sync callers still work (unawaited future), tests can now await to assert post-detach behavior
- discovered: iter 7
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/session_listener.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_07_session_listener_detach_drops_cancel_future_test.dart`
- summary: PluginSessionListener.detachSubscriptions returns before async EventSubscription cancellations finish, so a documented custom EventBinding can still deliver events after the host has detached.
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
lib/src/session_listener.dart:107:25: Error: A value must be explicitly returned from a non-void function.
```

## ISSUE-runtime-settings-tojson-leaks-live-config-maps

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: defensive deep-copy of nested config maps added at every PluginConfig/ServiceSettings/RuntimeSettings IN/OUT boundary (ctor cannot, but copyWith/fromJson/toJson/normalizer/getters all do)
- discovered: iter 10
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/settings.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_10_runtime_settings_tojson_leaks_live_config_maps_test.dart`
- summary: `RuntimeSettings.toJson()` returns live nested `config` maps instead of a detached JSON snapshot, so mutating the serialized output mutates the original settings object.
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
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_10_runtime_settings_tojson_leaks_live_config_maps_test.dart
00:00 +0: bug-hunt iter 10: runtime-settings-tojson-leaks-live-config-maps returns a detached plugin config snapshot from toJson
```

## ISSUE-runtime-settings-copywith-shares-config-maps

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: defensive deep-copy of nested config maps added at every PluginConfig/ServiceSettings/RuntimeSettings IN/OUT boundary (ctor cannot, but copyWith/fromJson/toJson/normalizer/getters all do)
- discovered: iter 11
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/settings.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_11_runtime_settings_copywith_shares_config_maps_test.dart`
- summary: `RuntimeSettings.copyWith()` returns a new top-level settings object that still shares the original `PluginConfig` and `ServiceSettings` config maps, so mutating the copied snapshot corrupts the original snapshot.
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
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_11_runtime_settings_copywith_shares_config_maps_test.dart
00:00 +0: bug-hunt iter 11: runtime-settings-copywith-shares-config-maps keeps plugin config isolated when mutating a copyWith snapshot
```

## ISSUE-runtime-settings-fromjson-shares-source-config-maps

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: defensive deep-copy of nested config maps added at every PluginConfig/ServiceSettings/RuntimeSettings IN/OUT boundary (ctor cannot, but copyWith/fromJson/toJson/normalizer/getters all do)
- discovered: iter 15
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/settings.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_15_runtime_settings_fromjson_shares_source_config_maps_test.dart`
- summary: RuntimeSettings.fromJson retains caller-owned nested `config` maps by reference, so mutating the source JSON after parsing silently mutates the parsed settings object.
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
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_15_runtime_settings_fromjson_shares_source_config_maps_test.dart
00:00 +0: bug-hunt iter 15: runtime-settings-fromjson-shares-source-config-maps detaches plugin config from source JSON after deserialization
```

## ISSUE-runtime-settings-config-getters-leak-live-maps

- status: CLOSED
- closed_at: 2026-05-17
- closed_reason: defensive deep-copy of nested config maps added at every PluginConfig/ServiceSettings/RuntimeSettings IN/OUT boundary (ctor cannot, but copyWith/fromJson/toJson/normalizer/getters all do)
- discovered: iter 16
- last_verified: 2026-05-17
- source file: `packages/plugin_kit/lib/src/settings.dart`
- failing test: `packages/plugin_kit/test/bug_hunt/iter_16_runtime_settings_config_getters_leak_live_maps_test.dart`
- summary: RuntimeSettings.getServiceConfig() and getPluginConfig() return live nested config maps, so mutating the returned map corrupts the original RuntimeSettings snapshot.
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
00:00 +0: loading /Users/saadardati/IdeaProjects/plugin_kit/packages/plugin_kit/test/bug_hunt/iter_16_runtime_settings_config_getters_leak_live_maps_test.dart
00:00 +0: bug-hunt iter 16: runtime-settings-config-getters-leak-live-maps returns a detached plugin config map from getPluginConfig
```


## ISSUE-20260518-1240-bind-callback-can-stop-cascade

- discovered: iter 15
- status: CLOSED
- closed_at: 2026-05-18
- closed_reason: emit/emitSync now capture preBindEvent, run bind callbacks, then revert both wrapped.event and _stopped if any bind called .stop(). 5-test regression suite covers emit+stop, emitSync+stop, emit+mutation, emitSync+mutation, and mixed precedence
- source file: `packages/plugin_kit/lib/src/event_bus.dart:115,688-704`
- doc reference: `website/src/content/docs/reference/event-bus-and-events.mdx:67`
- summary: A `bind` callback can call `EventEnvelope.stop()` and truncate typed handler dispatch, even though docs say `bind` cannot stop the cascade.
- repro: Register a `bind` callback that calls `event.stop()`, then emit an event with multiple typed handlers and observe later handlers do not run.
- severity: MEDIUM

## ISSUE-20260518-1240-dialog-marksaved-skipped-after-save-pop

- discovered: iter 15
- status: CLOSED
- closed_at: 2026-05-18
- closed_reason: PluginKitDialogBody._handleSave now calls markSaved() before the !mounted check, mirroring the existing finally block that clears isSaving regardless of mounted. Completer-gated regression test verified load-bearing via git stash
- source file: `packages/plugin_kit_dialog/lib/src/widgets/plugin_kit_dialog.dart:97-105; packages/plugin_kit_dialog/lib/src/widgets/plugin_kit_dialog_body.dart:153-163`
- doc reference: `website/src/content/docs/reference/dialog-api.mdx:195`
- summary: In the default `showPluginKitDialog` save flow, the route pops before `_handleSave()` resumes, so `markSaved()` is skipped when `!mounted` short-circuits.
- repro: Use `showPluginKitDialog` with default `onSave`, save successfully, and verify `isDirty` can remain true because `markSaved()` is not called.
- severity: MEDIUM
