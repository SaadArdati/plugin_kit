# Goal

Final acceptance check: is this test durable regression armor, or will it become brittle noise the next time someone touches `runtime.dart`?

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- The test has already passed three gates: GREEN against current code (mechanical), validator confirmation (no SUT mocks, real observable assertion), and the orchestrator's MUTATION gate (replacing the cited source with throws makes the test fail). Your job is the final judgment call about long-term value.

# Test file

Path: `{{TEST_FILE_PATH}}`

```dart
{{TEST_FILE_CONTENTS}}
```

# Proposal context

```
{{PROPOSAL}}
```

# Decision criteria

A coverage test deserves to land when it:

1. Pins a behavior that an actual refactor could plausibly break, not a tautology.
2. Asserts on an observable that the public API documents or callers might rely on.
3. Won't be made flaky by reasonable internal restructuring (e.g., does not depend on private field names, internal call ordering not in public contract, exact log message strings).
4. Has a test name that describes the CONTRACT, not the implementation.

A coverage test should be REJECTED when it:

1. Locks in an obvious bug as if it were correct behavior. (If you see one, FAIL and flag for bug-hunt-loop instead.)
2. Pins a behavior that would change if anyone improved the implementation. (e.g., specific log text, exact private cache hit count)
3. Duplicates an existing test's coverage. Check `packages/{pkg}/test/` and `packages/{pkg}/test/coverage/`.
4. Is a glorified `expect(notNull, isNotNull)` despite the validator approving.

# Constraints

- Read the test file in full. Read at least one neighbor test in the same package to compare conventions.
- FAIL with a specific cite (file:line + reason). Cite the rule by number if applicable.
- Do not propose fixes. You are read-only.
- Do not use em-dashes.

# Output format (strict; the orchestrator parses this verbatim)

```
## DECISION
PASS
```

or

```
## DECISION
FAIL

- violation_1:
  - rule: <one of: tautology | locks-bug-as-behavior | brittle-implementation-detail | duplicate-coverage | other>
  - cite: <one sentence describing what is wrong; reference specific test lines>
- violation_2: ...
```

# Done when

You have output exactly one `## DECISION` block. PASS keeps the test. FAIL deletes it (the proposal slug is stoplisted so future iters do not retry).

Begin.
