# Goal

Judge whether the fixer's edits actually resolve each validator-confirmed finding. Fix anything wrong inline yourself, do not punt to the next iteration. Produce a verdict-per-finding report.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- You see the fixer's report and a diff of the changed files. You do NOT see the fixer's reasoning narrative on purpose: it would bias you. Re-derive every verdict by reading the diff and the affected files.
- After you finish, an external verifier (`make doc-check`, `flutter test website/snippets`) runs. If it fails, the iteration is rolled back via snapshot restore. Make sure any code or snippet you touch still compiles.

# Fixer's report (what they claim to have done)

```
{{FIX_REPORT}}
```

# Diff of changed files (the ground truth)

The textual diff of every file the fixer touched is at:

```
{{DIFF_PATH}}
```

If that file is empty, the fixer made no changes; skip to the output section and emit `STATUS: NO_CHANGES`.

# Review protocol (per finding in the fix report)

For every entry whose action was `edit` or `append-issue`:

1. Open the original finding (its `claim`, `evidence_pointer`, and `note` are embedded in the fix report).
2. Read the relevant slice of `{{DIFF_PATH}}` to see exactly what changed.
3. If needed, read the full current state of the changed file to judge surrounding context.
4. Re-read the source-of-truth file at the evidence_pointer to know what the doc SHOULD say.
5. Decide independently:
   - Does the edit address the validator-confirmed claim?
   - Does it introduce any regression (broken link, drifted reference, wrong code in a snippet, em-dash, marketing tone, repeated content, broken `#docregion`)?
   - Did the fixer over-reach (touched something the finding does not justify)?

For entries marked `skip-already-fixed` or `skip-unfixable`: open the file and verify the skip was honest. If the issue is still present and you can fix it in-scope, fix it.

# Fixing inline

If you find any of the following, edit the file yourself before producing the final report. Smallest change that makes the file correct.

- The fixer's edit does not address the claim.
- The fixer introduced a regression (broken markdown, broken snippet region tag, drifted source reference, em-dash, marketing tone, content repeated from elsewhere).
- The fixer touched a file or region the confirmed finding does not justify.
- The fixer wrote a `PACKAGE_ISSUES.md` entry that duplicates an existing one or has wrong fields.

If a problem requires touching forbidden files (`packages/*/lib/src/`, `.git/`, infrastructure), mark the entry `UNFIXABLE` and let the next iteration handle it.

# Editing scope (same as the fixer)

Allowed:

- `website/src/content/docs/**/*.mdx`
- `website/snippets/lib/**/*.dart`
- `README.md`, every `packages/*/README.md`, `packages/*/example/README.md`
- `example/*/bin/*.dart`, `example/*/lib/**/*.dart`
- `PACKAGE_ISSUES.md` at the repo root
- Dartdoc comment lines (`///`) in `packages/*/lib/**/*.dart` only

Forbidden: same as the fixer. **Never commit. Never stage. Never run any git command.** The orchestrator manages git state.

# Package-source diff enforcement (HARD GATE)

For every changed file under `packages/*/lib/`:

1. Inspect the diff hunks in `{{DIFF_PATH}}`.
2. Every added or removed line MUST begin with `///` after leading whitespace. Empty `///` lines and `///` blocks of pure prose count as `///` lines.
3. Any added or removed line that is NOT a `///` line is a violation. Examples of violations: signature changes, removed `@override` annotations, modified method bodies, added imports, changed type parameters, edited inline `//` comments, touched `/* */` blocks.
4. Verify with: `awk '/^\+\+\+ b\/packages\/.*\/lib\// {f=$2; next} /^@@/ {next} f && /^[+-]/ && !/^[+-][[:space:]]*\/\/\// {print f": "$0}' {{DIFF_PATH}}` — this should print nothing.
5. If violations exist:
   - Restore the offending lines to their original (snapshot) state. Read the snapshot if needed, or compute the inverse hunk from the diff.
   - Mark the affected finding `UNFIXABLE` so the next iteration's auditor sees it as still open.
   - Append a note to `PACKAGE_ISSUES.md` for any finding that genuinely needs a code change (not a doc change).

This gate exists because dartdoc comments are documentation and may be freely fixed, but any change to actual code must go through human review (via `PACKAGE_ISSUES.md`), not auto-edit.

# Verification commands (use BEFORE confirming PASS)

- Snippet region tags balanced: `rg -n '#docregion <tag>|#enddocregion <tag>' website/snippets/lib/<file>` should show one of each per tag.
- Doc claim now matches source: `rg -n 'pattern' packages/.../foo.dart` and read the doc passage.
- MDX link resolves: `ls website/src/content/docs/<slug>/` exists.
- `PACKAGE_ISSUES.md` not duplicated: `rg -c 'ISSUE-' PACKAGE_ISSUES.md` and compare against the date stamps.
- Package-source diff is dartdoc-only: see the gate above.

Batch independent reads in parallel.

# Style re-checks the reviewer enforces

- No em-dashes in any prose touched this iteration.
- No bold/italic in dense reference paragraphs.
- Plugin/service/event ids stay lowercase snake_case, wrapped in typed handles.
- Doc claims about APIs must be re-verifiable in `packages/*/lib/src/`.
- Snippet region tags (`// #docregion`, `// #enddocregion`) intact and balanced.
- Internal MDX links resolve to existing slugs.
- Dartdoc `///` blocks remain attached to their declarations (no orphaned doc comments separated from the symbol they describe).

# Constraints

- Do NOT add fresh findings that were not in the fix report. New findings belong to the next iteration's auditor.
- Do NOT make stylistic edits outside the diffed regions unless they are a regression caused by the fixer.
- Do NOT compliment the fixer, narrate your judgments, or write a preamble. Output only the report.
- Do NOT use em-dashes.
- If `{{DIFF_PATH}}` is empty, output `STATUS: NO_CHANGES` and stop.

# Output format (strict)

```
## REVIEW REPORT iter {{ITERATION}}

### F1 <repo-relative file path>
- finding: F1
- verdict: PASS | FIXED_INLINE | UNFIXABLE
- note: <one sentence: what you confirmed, what you re-fixed, or why it is unfixable>

### F2 ...
```

Final line:

```
## SUMMARY iter {{ITERATION}} pass=<N> fixed_inline=<M> unfixable=<K>
```

# Done when

Every entry in the fix report has a verdict, every regression you found has been re-fixed (or marked `UNFIXABLE`), and the `SUMMARY` line is at the bottom of your output.

Begin.
