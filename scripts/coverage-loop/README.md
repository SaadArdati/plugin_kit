# coverage-loop

Autonomous loop that builds regression armor. Hunts for public-API behaviors that aren't currently tested and produces characterization tests that lock them in. Each test passes a four-gate cascade before landing.

## How to run

```bash
make coverage                            # default 15 iters
make coverage COVERAGE_MAX=30            # cap higher
make coverage-resume                     # resume last run
```

Or directly:

```bash
bash scripts/coverage-loop/orchestrator.sh --max 30
bash scripts/coverage-loop/orchestrator.sh --dry-run
bash scripts/coverage-loop/orchestrator.sh --resume scripts/coverage-loop/runs/<dir>
```

## Pipeline

```
HUNTER          read-only         proposes 1 untested behavior with file:line
   v
TEST-WRITER     workspace-write   writes packages/*/test/coverage/iter_NN_<slug>_test.dart
                                  test MUST pass against current code
   v
[GREEN GATE]                      orchestrator runs the test; must exit 0
                                  REJECT if test fails (wrong proposal or accidental bug)
   v
VALIDATOR       read-only         shape check: no SUT mocks, real observable
                                  assertion, exercises cited source path
   v
[MUTATION GATE]                   orchestrator backs up source, replaces cited
                                  lines with `throw UnimplementedError(...)`,
                                  re-runs test, restores source. Test MUST fail
                                  against mutated code. If it still passes, the
                                  test isn't actually testing the cited code.
   v
REVIEWER        read-only         final judgment: durable regression armor or
                                  brittle implementation-detail noise
```

## Why mutation testing matters here

LLM-generated tests have a tendency to write "happy path coverage theater" — tests that exercise a code path but assert on outputs that wouldn't change even if the path itself broke. Coverage-by-line-execution is meaningless if the assertion couldn't fail.

The mutation gate is empirical mutation testing for one line range: it physically corrupts the cited source, runs the test, and demands a failure. If the test passes against `throw UnimplementedError()` substituted into the cited code, the test isn't load-bearing for what it claims to be testing and is rejected.

This costs one extra test run per iteration but is the difference between regression armor and shelfware.

## What lands on disk

Successful iteration:

- `packages/<pkg>/test/coverage/iter_NN_<slug>_test.dart` — passes today, fails against the cited source mutation

Failed iteration: test file deleted, slug added to persistent stoplist with the reason (`no-green`, `validator-dropped`, `mutation-passed`, `reviewer-failed`).

## Working tree

```
scripts/coverage-loop/
  README.md
  orchestrator.sh
  prompts/
    hunter.md
    test-writer.md
    validator.md
    reviewer.md
  state/
    permanent-stoplist.md          (persistent across runs)
  runs/                            (per-run workspaces, gitignored)
    <timestamp>/
      orchestrator.log
      state/
        iteration.txt
        stoplist.md
      iters/
        iter-NN/
          hunt.prompt.md hunt.md
          test-writer.prompt.md test-writer.md
          green.out green.exit
          validate.prompt.md validated.md
          mutation.out mutation.exit
          review.prompt.md review.md
    latest -> <timestamp>
```

`runs/` is gitignored.

## Tuning

Edit constants at the top of `orchestrator.sh`:

- Per-stage codex model (`HUNTER_MODEL`, `TEST_WRITER_MODEL`, etc.)
- `STAGE_TIMEOUT_S`: 25 min per codex stage
- `TEST_TIMEOUT_S`: 10 min per single test run

## Relationship to bug-hunt-loop

- bug-hunt: looks for BUGS, requires the test to FAIL first (RED), then fixes
- coverage: looks for UNTESTED behavior, requires the test to PASS first (GREEN), then mutation-verifies it's load-bearing

They are complementary, not redundant. Coverage builds confidence to refactor; bug-hunt finds the things that need fixing first.
