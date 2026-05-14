# doc-audit-loop

Self-driving documentation quality loop built on `codex exec`. Four specialised
codex agents run in sequence (audit, validate, fix, review), gated by an
external `make` + `flutter test` verifier, looping until either the auditor
reports clean state or the iteration cap is hit. Bugs found in the package
source (rather than the docs) are tracked in `PACKAGE_ISSUES.md` at the repo
root. Codex agents never commit; the orchestrator never commits either.

## Design

The pipeline mirrors three well-studied patterns:

- **Reflection Pattern** (generator / evaluator split): each role gets a fresh
  codex process with no memory of the other roles, so the evaluator does not
  rubber-stamp the generator's claims.
- **Chain-of-Verification (CoVe)**: the validator sees the auditor's *claim*
  and *evidence pointer* only, never the auditor's reasoning. It re-derives a
  yes/no answer by reading the files in isolation. This is the main
  hallucination kill switch (`arXiv:2309.11495`).
- **Ralph Loop**: convergence is gated by an external verifier (`make
  doc-check`, `flutter test website/snippets`) rather than self-assessment.
  Persistent state lives in files (`stoplist.md`, snapshots, run logs), not in
  context windows.

A stoplist suppresses recurring false positives: if the validator drops a
claim, the orchestrator adds it to `state/stoplist.md` and the next auditor is
told never to raise it again. If the verifier rolls back a fix, the offending
findings also land on the stoplist so the next iteration finds a different
angle.

## Roles

| Stage | Sandbox | Model | Inputs | Outputs |
|---|---|---|---|---|
| auditor | read-only | `gpt-5.4` | doc surface + stoplist | `audit.md` (≤15 findings) |
| validator | read-only | `gpt-5.4` | `audit.md` + codebase | `validated.md` (confirmed / dropped) |
| fixer | workspace-write | `gpt-5.3-codex` | `validated.md` | edits + `fix-report.md` + maybe `PACKAGE_ISSUES.md` |
| reviewer | workspace-write | `gpt-5.3-codex` | `fix-report.md` + git diff | `review.md` (PASS / FIXED_INLINE / UNFIXABLE) |
| verifier | shell (no LLM) | – | working tree | `verifier.log` (GREEN / RED) |

`workspace-write` is intentional: it blocks `.git/index.lock` on macOS so
commits silently fail. The prompts also explicitly forbid every git command.

## Convergence

The loop stops when any of these is true:

- Auditor outputs `STATUS: CLEAN`.
- Two consecutive iterations end with `confirmed = 0` after validation.
- `--max` iterations reached (default 15).

## Layout

```
scripts/doc-audit-loop/
  README.md                 (this file)
  orchestrator.sh           main bash loop
  monitor.sh                tail / status / diff helper
  prompts/
    auditor.md              templated; orchestrator substitutes ITERATION, STOPLIST
    validator.md            templated; substitutes ITERATION, FINDINGS
    fixer.md                templated; substitutes ITERATION, CONFIRMED
    reviewer.md             templated; substitutes ITERATION, FIX_REPORT, DIFF_PATH
  runs/                     git-ignored; one timestamped subdir per run
    latest -> <newest run>
    <timestamp>/
      orchestrator.log
      CONVERGED             (only present if it ended cleanly)
      VERIFIER_FAILURES.md  (only present if at least one verifier failed)
      state/
        iteration.txt
        stoplist.md
        dropped-ledger.md
      snapshots/iter-NN/    (rollback safety net)
      iters/iter-NN/
        audit.prompt.md / audit.md
        validate.prompt.md / validated.md
        fix.prompt.md / fix-report.md
        review.prompt.md / review.md
        changes.diff
        verifier.log
```

`runs/` should be in `.gitignore`. The prompts and orchestrator are tracked.

## Usage

```bash
# full run (15-iter cap, ~6-10 hours wall time)
scripts/doc-audit-loop/orchestrator.sh

# tighter cap
scripts/doc-audit-loop/orchestrator.sh --max 5

# build prompts + iterate workdir, no codex calls
scripts/doc-audit-loop/orchestrator.sh --dry-run

# resume a prior run after a crash
scripts/doc-audit-loop/orchestrator.sh --resume scripts/doc-audit-loop/runs/<timestamp>

# monitor a running loop from another terminal
scripts/doc-audit-loop/monitor.sh         # tail -F latest log
scripts/doc-audit-loop/monitor.sh status  # iteration + tail + verifier status
scripts/doc-audit-loop/monitor.sh diff    # diff from most recent iter
scripts/doc-audit-loop/monitor.sh runs    # list all runs
```

## Prerequisites

- `codex` on `$PATH`, authenticated (`codex login` or ChatGPT login).
- `codex debug models` lists the slugs used by the orchestrator
  (`gpt-5.4`, `gpt-5.3-codex`). Update `orchestrator.sh` if these rotate.
- `flutter`, `make`, `python3`, `rg`, `diff` available.
- The repo must be a `codex`-trusted directory, or the orchestrator passes
  `--skip-git-repo-check`.

## Costs and safeguards

- Each iteration is up to 4 codex stages plus a make-driven verifier.
  Realistic wall time: 6 to 12 minutes per iteration.
- Hard caps: 25 min per stage (`STAGE_TIMEOUT_S`), 15 min for the verifier
  gate, 15 iterations total.
- A failed verifier rolls back the docs to the pre-fixer snapshot for that
  iteration. Snapshots are kept on disk; nothing is lost.
- The orchestrator runs no destructive git commands and the prompts forbid
  them; `git status` after a run shows only the doc edits the fixer applied.

## Tuning knobs (top of orchestrator.sh)

- `MAX_ITERS` – default 15.
- `STAGE_TIMEOUT_S` – per-stage timeout in seconds (default 1500).
- `VERIFIER_TIMEOUT_S` – timeout for the make + flutter test gate.
- `AUDITOR_MODEL`, `VALIDATOR_MODEL`, `FIXER_MODEL`, `REVIEWER_MODEL`.
- `DOC_SCOPE`, `PACKAGE_README_GLOBS` – the snapshot/restore surface.

## Iterating on the loop itself

When you find that the auditor keeps flagging the same kind of false positive,
strengthen the validator prompt (`prompts/validator.md`) under "Dropping
criteria" and rerun with `--resume`. When the auditor misses a real defect
class, extend "Taxonomy" or "Verification commands" in `prompts/auditor.md`.
Both files are versioned and meant to evolve.
