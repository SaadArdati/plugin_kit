# Goal

Apply the smallest correct edit for each validator-confirmed finding. Persist until every finding is either fixed, recorded in `PACKAGE_ISSUES.md` (for package bugs), or honestly marked as a skip. Do not re-litigate the findings.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- The validator has already eliminated hallucinations. Treat the confirmed list as the contract.
- After you finish, a reviewer reads your diff (not your prose) and may patch your edits. The external `make doc-check` + `flutter test website/snippets` gate runs after that; if it goes red, your iteration is rolled back via snapshot restore.

# Confirmed findings (the contract)

```
{{CONFIRMED}}
```

# Editing scope

Allowed to edit (full rewrite of prose / code in these surfaces):

- `website/src/content/docs/**/*.mdx`
- `website/snippets/lib/**/*.dart`
- `README.md`, every `packages/*/README.md`, `packages/*/example/README.md`
- `example/*/bin/*.dart`, `example/*/lib/**/*.dart`
- `PACKAGE_ISSUES.md` at the repo root (create if missing, append-only)
- `Makefile` ONLY if a finding explicitly cites a Makefile target

Allowed to edit (comment-lines only, see strict rule below):

- **Dartdoc comments (`///`) inside `packages/*/lib/**/*.dart`** — every `///` line on a public declaration is API documentation. You may change the prose of these comments to fix DOC_DRIFT, OVERSTATED, MISLEADING, QUALITY, etc. findings against them. You may NOT change anything else in the file.

Strict rule for `packages/*/lib/**/*.dart`:

- Only lines that begin with `///` (after leading whitespace) may be added, deleted, or modified.
- Inline `// ` comments and `/* */` blocks are off-limits even though they are also comments — they typically encode internal rationale you do not own.
- Method bodies, signatures, imports, class members, annotations, types: untouchable. If a fix would require changing executable code, you must instead append an entry to `PACKAGE_ISSUES.md` and mark the finding `skip-unfixable`.
- The reviewer will diff each touched package-source file and reject the iteration if any non-`///` line changed.

Forbidden entirely (route to `PACKAGE_ISSUES.md` instead if a fix would require touching these):

- Any executable code in `packages/*/lib/` (signatures, bodies, declarations, annotations, imports). Even if it would fix the finding.
- Any file under `packages/*/test/` or `website/snippets/test/`.
- Any `.git/` operation. Never commit, never stage, never run `git add`, `git commit`, `git stash`, `git push`, or any destructive git command. The orchestrator manages git state.
- Any infrastructure file: `.github/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, build scripts, lock files.

# Routing by category

| Category | Action |
|---|---|
| `DOC_DRIFT`, `STALE_SNIPPET`, `MISLEADING`, `OVERSTATED`, `BROKEN_REF` | Edit the cited doc/snippet/README/dartdoc to match the source. Smallest change that resolves the claim. If the finding cites a dartdoc `///` line, edit only that comment block. |
| `REPETITION`, `REDUNDANT` | Delete or merge. Preserve any unique nuance from the deleted passage. |
| `QUALITY` | Tighten the prose without rewriting more than needed. Apply the project style below. |
| `PACKAGE_BUG` | Do NOT edit the package source code. Append an entry to `PACKAGE_ISSUES.md` (format below). If the entry already exists, do not duplicate. Dartdoc fixes are NOT package bugs — they are docs. |

# Project style (enforce on every prose change)

- No em-dashes (`—` / `--`). Use commas, parentheses, or two sentences.
- No bold or italic emphasis in dense reference prose. Tables and code blocks are fine.
- Plugin/service/event identifiers: lowercase snake_case, wrapped in their typed handle (`PluginId('foo')`, not raw strings).
- Don't add comments to code unless the WHY is non-obvious.
- For Flutter widget code: never `Widget _buildX(...)` helpers; inline the tree or extract a real widget class.
- Marketing tone in reference docs is a defect. State facts.

# Verification commands (use BEFORE editing and AFTER editing)

Codex produces better edits when it verifies before and after. Batch independent reads in parallel.

Before editing:

- Re-read the doc passage at `file:lines` to make sure the validator's claim still applies.
- Re-read the source-of-truth file at the evidence_pointer to know what the correct text should say.

After editing:

- For doc claims about an API: `rg -n 'symbol' packages/` to confirm the doc now matches the source.
- For snippet edits: `rg -n '#docregion <tag>' website/snippets/lib/` to confirm region tags are intact and balanced.
- For internal MDX link fixes: `ls website/src/content/docs/<slug>/` to confirm the slug now resolves.
- For `PACKAGE_ISSUES.md` appends: re-read the file to confirm no duplicate entry.

You do NOT need to run `make` or `flutter test`. The orchestrator runs them after the reviewer.

# `PACKAGE_ISSUES.md` shape

If the file does not exist, create it with this header:

```markdown
# Package Issues (auto-tracked by doc-audit loop)

This file is populated by the documentation audit loop when the docs describe correct behavior but the source code has a bug. Manual edits welcome; entries are append-only.
```

Each entry:

```markdown
## ISSUE-YYYYMMDD-HHMM-<short-slug>

- discovered: iter {{ITERATION}}
- source file: `packages/.../foo.dart:120-140`
- doc reference: `website/src/content/docs/.../bar.mdx:42-45`
- summary: one sentence stating the bug.
- repro: brief hint at how to reproduce.
- severity: HIGH | MEDIUM | LOW (carry over from the finding)
```

Use the current UTC date/time for the slug timestamp.

# Constraints

- Touch only files justified by the confirmed findings. No unrelated cleanup, even tempting cleanup.
- Apply byte-exact edits. Preserve indentation, line endings, and trailing newlines.
- If a finding is no longer applicable (the file already looks right, an earlier iteration handled it), mark it `skip-already-fixed`. Do NOT edit anyway "to be safe".
- If a finding is unfixable in scope (would require a forbidden file), mark it `skip-unfixable`. The reviewer handles escalation.
- Do not narrate progress, write a plan, or insert preamble. Go straight to file reads and edits, then to the report.
- Do not use em-dashes in your output.

# Output format (strict; the reviewer parses this)

Once all edits are applied:

```
## FIX REPORT iter {{ITERATION}}

### F1 <repo-relative path of primary file edited>
- finding: F1
- action: edit | append-issue | skip-already-fixed | skip-unfixable
- summary: one sentence describing what changed
- diff_hint: <optional 3-5 line snippet centered on the change>

### F2 ...
```

Final line:

```
## SUMMARY iter {{ITERATION}} edits=<N> issues_appended=<M> skips=<K>
```

# Done when

Every confirmed finding has an entry in your fix report with a clear `action`, the corresponding file changes are on disk, any `PACKAGE_BUG` findings have appended entries in `PACKAGE_ISSUES.md`, and the `SUMMARY` line is at the bottom of your output.

Begin.
