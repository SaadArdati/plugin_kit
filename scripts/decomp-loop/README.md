# decomp-loop

Executes the runtime decomposition spec
(`docs/superpowers/plans/2026-05-16-runtime-decomposition.md`) one step at a
time. Codex executor runs the spec section in a workspace-write sandbox, then
the orchestrator runs multiple gates (analyze, test, grep, signatures,
line-count), then a codex reviewer judges the diff shape. On full pass the
diff is staged and the loop STOPS, waiting for the user to commit manually.
The user runs `make decomp-resume` to advance to the next step.

## Why no auto-commit

Per user instruction. Refactor-class commits deserve human review of the
staged diff before they land. The orchestrator does everything up to the
commit boundary (gates, staging, generating the commit message file) and then
stops.

## How to run

```bash
make decomp                                   # run next pending step
make decomp-resume                            # resume in the same run dir
bash scripts/decomp-loop/orchestrator.sh --dry-run   # gates only, no codex
bash scripts/decomp-loop/orchestrator.sh --step 1    # force a specific step
make decomp-dashboard                         # open dashboard at #loop=decomp
```

After a successful step:

```bash
git diff --cached                                          # review the staged diff
git commit -F scripts/decomp-loop/runs/latest/steps/step-NN/commit-message.txt
make decomp-resume                                          # advance
```

## Step list

Eight actionable steps (Step 4 is REMOVED per spec round-2 consolidation):

| Dir       | Spec id | Title                                         |
| --------- | ------- | --------------------------------------------- |
| step-00   | 0       | dispose pilot                                 |
| step-01   | 0a      | public API contract test + test scaffolding   |
| step-02   | 1       | SettingsNormalizer extraction                 |
| step-03   | 2       | EnablementResolver extraction                 |
| step-04   | 3       | dispose pilot generalization (forwarders)     |
| step-05   | 5       | init + plugin-add extension                   |
| step-06   | 6       | session ownership plumbing                    |
| step-07   | 7       | reconcile + transactional cluster             |

The orchestrator tracks completed steps by scanning `git log` for the commit
template `refactor(plugin_kit): extract <cluster> [step N of 8]`. Resume picks
up where the most recent matching commit left off.

## Pipeline per step

```
WORKING TREE CHECK    must be clean (status.porcelain empty modulo decomp-loop/)
   v
EXTRACT               orchestrator awk-slices the spec section into prompt
   v
EXECUTOR              codex applies the step (workspace-write sandbox)
   v
[GATE analyze]        flutter analyze packages/plugin_kit (zero warnings)
   v
[GATE test]           flutter test packages/plugin_kit (all pass)
   v
[GATE grep]           per-step section-7 grep gates from spec
                        - all runtime/*.dart files declare part of '../plugin.dart';
                        - settings_normalizer.dart no Plugin token, no plugin.dart import
                        - enablement.dart no _-prefixed identifiers except _runtimeLog/_log
   v
[GATE signatures]     all public PluginRuntime method signatures still present
   v
[GATE line-count]     soft sanity gate (always passes; visible in dashboard)
   v
DIFF SNAPSHOT         git diff > diff.patch
   v
REVIEWER              codex reads diff + spec section + executor report;
                        verdict PASS or FAIL with cited violations
   v
STAGE                 git add only files changed by this step (never -A)
   v
COMMIT MESSAGE        write commit-message.txt with the spec's template
   v
HALT                  status=READY_FOR_COMMIT; user reviews and commits
```

Any gate failure halts the loop with `status=BLOCKED` and a specific reason
in `status.txt`. Nothing is staged on failure.

## Streaming and the dashboard

The orchestrator writes `phase.txt` continuously as a step progresses
(`starting -> executor -> analyze -> test -> grep -> signatures -> reviewer
-> staging -> ready`). The dashboard polls every 2 seconds and surfaces:

- The step id and cluster label in dedicated columns
- A Phase column that updates live without waiting for the step to end
- Per-gate PASS/FAIL columns (Anlz, Test, Grep, Sigs)
- Reviewer decision
- Live line count of runtime.dart so you can watch it shrink

Auto-tab-switching follows the pipeline order: as each new artifact lands
(executor output, then analyze, then test, etc.), the dashboard switches to
the freshest tab unless the user manually picked one in the last 10 seconds.

## What lands on disk per step

```
runs/<timestamp>/
  orchestrator.log
  steps/
    step-NN/
      step.txt              spec step id (e.g. "0", "0a", "1")
      title.txt             human-readable step title
      cluster.txt           commit-message <cluster> token
      phase.txt             updates continuously; freshest phase name
      status.txt            terminal: READY_FOR_COMMIT | BLOCKED <reason>
      spec-section.md       awk-extracted spec section for this step
      executor.prompt.md    rendered codex prompt
      codex.out             executor structured report
      codex.exit            executor exit code
      codex.stderr          executor stderr (codex progress events)
      analyze.out, .exit
      test.out, .exit
      grep-gates.out, .exit
      signatures.out, .exit
      line-count.out, .exit
      diff.patch
      review.prompt.md
      review.md             reviewer decision (PASS | FAIL)
      review.stderr
      commit-message.txt    ready to feed to `git commit -F`
```

The persistent `state/progress.log` appends a line per step `READY_FOR_COMMIT`
event, surviving across run dirs.

## Working tree

```
scripts/decomp-loop/
  README.md
  orchestrator.sh
  prompts/
    step-executor.md       codex prompt for the executor stage
    reviewer.md            codex prompt for the reviewer stage
  state/
    progress.log           persistent append-only log of READY events
  runs/                    gitignored
    <timestamp>/
      ...
    latest -> <timestamp>
```

## Tuning

Edit at the top of `orchestrator.sh`:

- `EXECUTOR_MODEL` (default `gpt-5.3-codex`): the codex executor model
- `REVIEWER_MODEL` (default `gpt-5.4`): the codex reviewer model
- `STAGE_TIMEOUT_S` (default 1500s): per-codex-stage timeout

Override via env vars: `DECOMP_EXECUTOR_MODEL`, `DECOMP_REVIEWER_MODEL`,
`DECOMP_STAGE_TIMEOUT_S`.

## Relationship to other loops

| Loop      | Iteration model                  | Commits | Source             |
| --------- | -------------------------------- | ------- | ------------------ |
| doc-audit | hunt-fix until converged         | yes     | none (codex hunts) |
| bug-hunt  | hunt one bug per iter            | no      | none               |
| coverage  | hunt one behavior per iter       | no      | none               |
| decomp    | execute fixed sequence per spec  | NO (user commits manually) | the spec doc |

decomp is the first loop driven by a spec document. The spec is the contract;
the loop mechanically executes it.
