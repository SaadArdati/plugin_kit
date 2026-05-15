# Goal

Decide whether the passing test is a real characterization test (vs trivial / implementation-coupled / accidentally a bug reproducer that just happens to pass).

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- You see the test file and the GREEN output only. The orchestrator already verified the test exits 0; your job is to confirm it pins meaningful behavior.
- A downstream MUTATION gate (orchestrator-driven, not yours) will then corrupt the cited source and re-run the test, requiring it to fail. So the test must be CAUSALLY connected to the cited source.

# Test file

Path: `{{TEST_FILE_PATH}}`

```dart
{{TEST_FILE_CONTENTS}}
```

# GREEN output

```
{{GREEN_OUTPUT}}
```

# Decision criteria (DROP unless ALL are true)

1. The test passes via a real assertion that compares against an EXPECTED value, not via the absence of throws or trivially-true comparisons. `expect(x, isNotNull)` on a non-nullable return type is trivial. `expect(true, isTrue)` is trivial.
2. The test uses **real instances** of the SUT. Mocks of `PluginRuntime`, `ServiceRegistry`, `EventBus`, `PluginSession`, or the package's controllers/services invalidate it.
3. The test asserts on **observable behavior** (return value, state, side effect, thrown exception type), not on internal implementation details (private fields, mock invocation counts, log line text matching).
4. The test exercises the cited source path. If the cited source is `runtime.dart:1200-1210` (some specific reconcile branch) but the test calls a different unrelated method, the test won't fail the mutation gate and is meaningless.
5. The test is minimal: under 60 lines, one behavior per test.

Any violation -> DROP.

# Constraints

- You are read-only. Do not propose fixes. Do not edit anything.
- Reject with a specific cite: "expect at line 24 is `expect(x, isNotNull)` on a non-nullable return; trivially true" is acceptable.
- Do not use em-dashes.

# Output format (strict; the orchestrator parses this verbatim)

```
## DECISION
CONFIRMED

- contract_under_test: <one sentence describing the behavioral contract>
- behavior_asserted: <one sentence describing the specific observable the test pins>
- real_instances: <comma-separated list of SUT types instantiated>
```

Otherwise:

```
## DECISION
DROPPED

- reason: <one sentence citing the specific test line or output line that disqualifies it>
```

# Done when

You have output exactly one `## DECISION` block.

Begin.
