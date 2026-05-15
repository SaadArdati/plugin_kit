# Goal

Write a Dart characterization test that locks in the proposed untested behavior. The test MUST PASS against current code. You do NOT edit source code; only create the test file.

# Discipline (NON-NEGOTIABLE)

You are NOT writing a bug reproducer here. This loop pins CURRENT BEHAVIOR.

- The test MUST PASS when run against current source. If it fails, you either misidentified the behavior or accidentally found a bug. In both cases, output `## STATUS\nINFEASIBLE` with a one-sentence reason.
- Use real code. NO mocks of the system under test. If the proposal involves `PluginRuntime`, you instantiate a real `PluginRuntime`. Mocks of `system under test` invalidate the test.
- One behavior per test. Tests with two unrelated assertions are not characterization tests; they are misclassified.
- Test the behavior, not the implementation. Assert on observable outcomes (state, return values, thrown exceptions, side effects), not on internal method calls.
- The test must be NON-TRIVIAL. A test that passes regardless of what the source does (e.g., `expect(true, isTrue)`) is rejected by the mutation gate downstream anyway; don't bother writing one.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- The hunter has proposed an untested behavior. You write the characterization test.

# Proposal to test

```
{{PROPOSAL}}
```

# Where to place the test

Coverage tests live in their own directory, isolated from existing tests:

| Package | Directory | Filename pattern |
|---|---|---|
| `plugin_kit` | `packages/plugin_kit/test/coverage/` | `iter_{{ITERATION_PADDED}}_<slug_snake>_test.dart` |
| `plugin_kit_dialog` | `packages/plugin_kit_dialog/test/coverage/` | `iter_{{ITERATION_PADDED}}_<slug_snake>_test.dart` |
| `flutter_plugin_kit` | `packages/flutter_plugin_kit/test/coverage/` | `iter_{{ITERATION_PADDED}}_<slug_snake>_test.dart` |

`<slug_snake>` MUST be `lower_case_with_underscores`. Convert every `-` in the hypothesis slug to `_` before constructing the filename.

# Test name should describe the contract being pinned

GOOD: `'updateSettings rolls back per-session enablement on partial failure'`

BAD: `'updateSettings test'`

# Constraints

- Create EXACTLY ONE new test file. Do not edit existing test files. Do not edit any production code.
- Do not import internal libraries (anything under `lib/src/`). Use the package's public API only.
- Do not use mocks for `PluginRuntime`, `ServiceRegistry`, `EventBus`, `PluginSession`, etc.
- Do not write more than 60 lines of test code.
- Do not use em-dashes.
- Do not narrate.

# Output format (strict; the orchestrator parses this verbatim)

```
## STATUS
TEST_WRITTEN
```

(or `INFEASIBLE` with a one-sentence reason.)

Then:

```
## TEST_FILE
<repo-relative path>

## PACKAGE
plugin_kit | plugin_kit_dialog | flutter_plugin_kit

## TEST_NAMES
- "<exact test name from the test(...) call>"

## NOTES
<2-3 lines describing what the test pins and why this characterization is durable across reasonable refactors.>
```

# Done when

The test file exists, contains exactly one passing test that asserts the proposed behavior, and the report is written.

Begin.
