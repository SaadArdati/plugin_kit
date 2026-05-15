# bug-hunt-loop

Autonomous TDD-enforced bug-hunt loop that targets `packages/plugin_kit/`, `packages/plugin_kit_dialog/`, and `packages/flutter_plugin_kit/`. Each iteration hypothesizes one bug, proves it with a failing test (RED), applies a minimal fix (GREEN), and either commits both test and fix to disk or rolls the fix back and files a `PACKAGE_ISSUE` while keeping the test as evidence.

**The orchestrator never commits.** It only writes files under the working tree.

## How to run

```bash
make bug-hunt                          # default 15 iters
make bug-hunt BUG_HUNT_MAX=30          # cap higher
make bug-hunt-resume                   # resume last run after crash / interrupt
```

Or directly:

```bash
bash scripts/bug-hunt-loop/orchestrator.sh --max 30
bash scripts/bug-hunt-loop/orchestrator.sh --dry-run     # renders prompts only
bash scripts/bug-hunt-loop/orchestrator.sh --resume scripts/bug-hunt-loop/runs/<dir>
```

## Pipeline

```
HUNTER          read-only         hypothesize 1 bug with file:line + repro_strategy
   v
TEST-WRITER     workspace-write   create test/bug_hunt/iter_NN_<slug>_test.dart
   v
[ORCHESTRATOR]                    run `dart test <file>` or `flutter test <file>`
                                  capture stdout/stderr, exit code, timestamp
                                  REJECT if exit==0 or output is COMPILE_ERROR
   v
VALIDATOR       read-only         CoVe-style: sees test + RED output only.
                                  Drops on weak repros or SUT mocks.
   v
[ORCHESTRATOR]                    snapshot packages/<pkg>/lib + test file
   v
FIXER           workspace-write   minimal edit to lib/. forbidden to touch test.
   v
[ORCHESTRATOR]                    TDD gate 1: test file byte-unchanged?
                                  TDD gate 2: lib/ diff non-empty?
                                  run FULL `dart test` or `flutter test` (GREEN)
                                  REJECT if any test fails.
   v
REVIEWER        read-only         catches what mechanical gates cannot:
                                  - flutter-architecture CRITICAL rules
                                  - TDD rationalizations (workaround vs root-cause)
                                  - unrelated refactor, test-only API hooks
```

## TDD enforcement (machine-checked)

1. **RED before GREEN**: the orchestrator runs the test in isolation BEFORE the fixer can edit anything. Exit code must be non-zero AND output must classify as `ASSERTION_FAIL` (not `COMPILE_ERROR`).
2. **Test file frozen**: the orchestrator snapshots the test file immediately after RED. If the fixer modifies it, the iteration rolls back automatically.
3. **Production diff non-empty**: the fixer must actually edit `packages/<pkg>/lib/`. An empty diff is treated as `FIX_TOO_LARGE` and rolled back.
4. **Full suite green**: after the fixer runs, the orchestrator runs the package's complete test suite. Any regression rolls back the fix.
5. **Reviewer pass**: codex reviewer applies the flutter-architecture skill's CRITICAL rules (scope-aware) and TDD red flags. FAIL also rolls back.

## Stuck-fix policy

When the fix cannot land (validator dropped, fixer declined `FIX_TOO_LARGE`, lib diff empty, GREEN failed, reviewer FAILED), the orchestrator:

1. Restores `packages/<pkg>/lib/` from snapshot
2. Wraps the failing test file with a library-level `@Skip('ISSUE-...: ...')` annotation so the test stays committed but no longer fails the suite
3. Appends an entry to `PACKAGE_ISSUES.md` at the repo root with the bug summary, source citation, test path, severity, and a 20-line RED excerpt
4. Stoplists the slug so the hunter does not re-discover it next iteration

The failing test is durable evidence; whoever picks up the issue inherits a ready-made regression test.

## Scope rules (flutter-architecture, applied by reviewer)

| Package | CRITICAL rules applied |
|---|---|
| `plugin_kit` (pure Dart) | CRITICAL-3 (one concern), -5 (abstract deps), -8 (no sibling refs), -9 (typed identifiers) |
| `plugin_kit_dialog` (Flutter widgets) | All 10 CRITICAL rules |
| `flutter_plugin_kit` (Flutter bridges) | All 10 CRITICAL rules |

The reviewer enforces these against the fixer's diff, not the surrounding code.

## What lands on disk

Successful iteration:

- `packages/<pkg>/test/bug_hunt/iter_NN_<slug>_test.dart` (new, passing)
- `packages/<pkg>/lib/...` (modified, minimal diff)

Stuck iteration:

- `packages/<pkg>/test/bug_hunt/iter_NN_<slug>_test.dart` (new, library-level `@Skip`, still committable)
- `PACKAGE_ISSUES.md` (new entry appended)
- `packages/<pkg>/lib/...` (UNCHANGED, restored from snapshot)

## Working tree

Every run lives under `scripts/bug-hunt-loop/runs/<timestamp>/`:

```
runs/
  20260515-1023/
    orchestrator.log
    state/
      iteration.txt
      stoplist.md
    iters/
      iter-01/
        hunt.prompt.md       hunt.md
        test-writer.prompt.md test-writer.md
        test-file.red.dart   (frozen RED-state copy of the test)
        red.out red.exit red.ts
        validate.prompt.md   validated.md
        fix.prompt.md        fix-report.md
        green.out green.exit green.ts
        lib.diff             (production diff vs snapshot)
        review.prompt.md     review.md
      iter-02/ ...
    snapshots/
      iter-01/ lib/...       (auto-pruned to most recent)
  latest -> 20260515-1023
```

`runs/` is gitignored. The dashboard from `scripts/doc-audit-loop/dashboard/` is doc-audit-specific and is NOT wired to this loop; tail `orchestrator.log` directly to monitor a run.

## Recovery

Each codex stage has a 25-minute timeout (OpenAI tail-latency can spike). On hang or crash:

```bash
make bug-hunt-resume        # picks up at last completed iteration
```

The orchestrator reads `state/iteration.txt` and continues from `iter + 1`. The stoplist accumulates across resumes so already-found bugs are not re-discovered.

## Tuning

Edit the constants at the top of `orchestrator.sh`:

- `HUNTER_MODEL`, `TEST_WRITER_MODEL`, etc.: per-stage model selection
- `STAGE_TIMEOUT_S`: per codex stage (default 1500s)
- `TEST_TIMEOUT_S`: per single test file run (default 600s)
- `SUITE_TIMEOUT_S`: per full package suite run (default 1200s)

If a particular package's suite is slow, raise `SUITE_TIMEOUT_S`. If codex stages keep timing out on a small package, lower `STAGE_TIMEOUT_S` to fail faster.
