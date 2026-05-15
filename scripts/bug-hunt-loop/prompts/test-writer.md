# Goal

Write a single failing Dart test that reproduces the hypothesized bug. The test MUST fail when run against the current source. You do NOT edit source code; only create the test file.

# TDD discipline (NON-NEGOTIABLE)

You are the RED step of a strict TDD cycle. Reading this prompt means you have committed to these rules:

- Write the test BEFORE any production code changes. (The orchestrator forbids production edits at this stage.)
- The test MUST fail. A test that passes immediately proves nothing - it tests existing behavior, not the bug.
- Use real code. NO mocks of the system under test. If the bug involves `PluginRuntime`, you instantiate a real `PluginRuntime`. Mocks of `system under test` invalidate the test.
- One behavior per test. If you write `expect(a).toBe(b); expect(c).toBe(d)` covering unrelated invariants, split it.
- Test the behavior, not the implementation. Assert on observable outcomes (state, return values, thrown exceptions, side effects), not on internal method calls.

If you cannot meet these rules without modifying source code, output `## STATUS\nINFEASIBLE` and a one-sentence reason. Do not write a passing test.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- The hunter has flagged exactly one bug. You must turn it into a failing reproducer.

# Hypothesis to reproduce

```
{{HYPOTHESIS}}
```

# Validator feedback from a previous attempt (if any)

{{REWRITE_GUIDANCE}}

If the block above is empty, this is your first attempt; ignore it. If it contains validator guidance, your previous test was rejected for a specific shape problem (mock of SUT, wrong assertion, compile failure rather than runtime failure, etc.). The bug itself is still presumed real; you are rewriting the TEST, not abandoning the hypothesis. Apply the guidance literally before considering anything else.

# Where to place the test

Bug-hunt tests live in their own directory, isolated from the existing test suites:

| Package | Directory | Filename pattern |
|---|---|---|
| `plugin_kit` | `packages/plugin_kit/test/bug_hunt/` | `iter_{{ITERATION_PADDED}}_<slug_snake>_test.dart` |
| `plugin_kit_dialog` | `packages/plugin_kit_dialog/test/bug_hunt/` | `iter_{{ITERATION_PADDED}}_<slug_snake>_test.dart` |
| `flutter_plugin_kit` | `packages/flutter_plugin_kit/test/bug_hunt/` | `iter_{{ITERATION_PADDED}}_<slug_snake>_test.dart` |

`<slug_snake>` MUST be lowercase letters, digits, and underscores only. The hypothesis's `slug` is kebab-case (hyphens); convert every `-` to `_` before constructing the filename. Dart's `file_names` lint flags hyphens in `.dart` filenames; a violation here is grounds for the reviewer to fail the iteration.

Example: hypothesis slug `session-listener-stale-after-swap` -> filename `iter_07_session_listener_stale_after_swap_test.dart`.

Create the `bug_hunt/` subdirectory if it does not exist.

# Test file template (read carefully; pick the right runner)

For `plugin_kit` (pure Dart):

```dart
import 'package:plugin_kit/plugin_kit.dart';
import 'package:test/test.dart';

void main() {
  group('bug-hunt iter {{ITERATION}}: <slug>', () {
    test('<one-line behavioral description matching expected behavior>', () async {
      // Construct the scenario described in repro_strategy.
      // Real instances only. No fakes/mocks of SUT.
      // Drive the operation that exposes the bug.
      // Assert the EXPECTED behavior (per hypothesis), not the actual.
      // This assertion MUST FAIL on the current code.
    });
  });
}
```

For `plugin_kit_dialog` or `flutter_plugin_kit` (Flutter):

```dart
import 'package:flutter_test/flutter_test.dart';
// import the relevant package as needed

void main() {
  group('bug-hunt iter {{ITERATION}}: <slug>', () {
    test('<one-line behavioral description matching expected behavior>', () async {
      // For widget-level bugs, use testWidgets(...) instead and pump the widget tree.
      // For state-holder bugs, prefer plain `test(...)` to keep the harness minimal.
    });
  });
}
```

The test name MUST describe what the code SHOULD do, not what it does. Example for a `ROLLBACK_GAP`:

- GOOD: `'restores prior settings snapshot when rollback fails partway'`
- BAD: `'best-effort rollback may leave partial state'` (describes the bug, not the contract)

# Verification commands (use BEFORE finalizing the test)

Codex produces stronger reproducers when it actually verifies the failure. Run these in this order:

- Read the source code around the cited file:line to confirm the failure mode is exactly what you expect.
- Read 1-2 existing tests in the SAME package (e.g. `ls packages/{pkg}/test/`) to learn the test conventions: how `PluginRuntime` is built, what helpers exist, how teardown is handled.
- After writing the test file, you do NOT need to run `dart test` yourself - the orchestrator runs it next and captures the failure output. But your test must be syntactically valid Dart.

# Constraints

- Create EXACTLY ONE new test file. Do not edit existing test files. Do not edit any production code.
- Do not import internal libraries (anything under `lib/src/`). Use the package's public API only.
- Do not use `Mockito`, `Mocktail`, or hand-rolled mocks of the system under test. Test doubles for repositories or external collaborators are acceptable; mocks of `PluginRuntime`, `ServiceRegistry`, `EventBus`, etc., are not.
- Do not add `try`/`catch` around the assertion to "make sure it fails". If the bug throws, use `expect(() => ..., throwsA(...))`. If the bug produces wrong state, assert on the state.
- Do not write more than 60 lines of test code (including setup). If the repro needs more, the hypothesis is too large for this loop.
- Do not use em-dashes.
- Do not narrate. Go straight to file reads, then write the file, then output the report.

# Output format (strict; the orchestrator parses this verbatim)

```
## STATUS
TEST_WRITTEN
```

(or `INFEASIBLE` with a one-sentence reason if the bug cannot be reproduced without modifying source code or external systems.)

Then:

```
## TEST_FILE
<repo-relative path to the new test file>

## PACKAGE
plugin_kit | plugin_kit_dialog | flutter_plugin_kit

## TEST_NAMES
- "<exact test name from the test(...) call>"

## REPRO_NOTES
<2-3 lines describing exactly what the test does and why it must fail on current code.>
```

# Done when

The test file exists at the cited path, contains exactly one failing test that asserts the EXPECTED behavior, uses real instances only, and the report is written.

Begin.
