# Goal

Find real, citable defects in the plugin_kit documentation by cross-referencing every factual claim against the current Dart source code. Produce a structured report the next agent will validate.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}} (cap is 15).
- Earlier iterations have already applied fixes; do NOT re-flag issues that no longer exist in the current files.
- The downstream pipeline is: validator (drops hallucinations) → fixer (edits) → reviewer → external verifier (`make doc-check`, `flutter test website/snippets`). Your job ends at producing the finding list.

# Documentation surface (everything in scope)

Sample broadly. Each iteration, rotate which subtree you focus on so you don't tunnel.

- `website/src/content/docs/**/*.mdx` (~39 files: concepts, guides, reference, examples, getting-started, troubleshooting, faq, why-plugin-kit, introduction)
- `website/snippets/lib/**/*.dart` (the snippets the MDX pages embed via `extractRegion` and `#docregion` tags)
- `website/snippets/test/**/*.dart` (tests that pin snippet correctness)
- Root `README.md` plus every `packages/*/README.md` and `packages/*/example/README.md`
- Example apps and CLIs: `example/villain_lair/bin/*.dart`, `example/state_garden/lib/**/*.dart`, `example/code_editor/{lib,bin}/**/*.dart`, `example/model_embassy/bin/*.dart`, `example/plugin_kit_dialog_demo/lib/**/*.dart`
- `Makefile` (only if a doc claims a make target exists, or claims a regeneration command)
- **Dartdoc comments (`///`) in `packages/*/lib/**/*.dart`** — every triple-slash block on a public declaration is documentation that ships to API users via pub.dev. Audit them with the same standards as MDX prose: factual accuracy against the surrounding code, no overstated claims, no stale signatures, no broken `[ClassName]` references. Inline `// ` comments and `/* */` blocks inside method bodies are NOT documentation; ignore them.

# Source of truth (what factual claims must match)

- `packages/plugin_kit/lib/src/**/*.dart`
- `packages/plugin_kit_dialog/lib/src/**/*.dart`
- `packages/flutter_plugin_kit/lib/src/**/*.dart`

If a doc names an API, default, exception, phase, return type, class, flag, or behavior, the claim is wrong unless you read it in one of those source files. When auditing a dartdoc comment, the source of truth is the executable code in the SAME file (the method body, the class members, the actual return type) right beside the comment.

# Stoplist (DO NOT re-raise these; they have been rejected by prior validators)

{{STOPLIST}}

# Verification commands (use these BEFORE flagging)

Codex produces better audits when it actually verifies its claims. Use the tools available; batch independent file reads in parallel.

- Find a symbol's definition: `rg -n 'class FooBar' packages/`
- Find every reference: `rg -n 'FooBar' packages/ website/ example/`
- Check a snippet region tag exists in its `.dart` file: `rg -n '#docregion my-tag' website/snippets/lib/`
- Confirm a make target: `grep -E '^[a-z_-]+:' Makefile`
- Read a specific MDX excerpt: `sed -n '40,80p' website/src/content/docs/reference/architecture.mdx`

If you cannot verify a claim by reading the actual files, do NOT flag it.

# Constraints

- Read at least one doc passage and at least one source file before flagging. Never flag from memory or from the doc alone.
- One finding per file:line pair. Three problems in one paragraph is three findings.
- Maximum 15 findings per iteration. Pick the highest-severity first. If you have fewer than 15 HIGH/MEDIUM issues after a broad sample, stop early; do not pad with LOW.
- Do not propose fixes, narrate reasoning, or write a preamble. Go straight to verification, then to the report.
- Do not mention stoplist items, even to explain why you skipped them.
- Do not flag duplicates of issues already in your own report.
- For every QUALITY / REDUNDANT / REPETITION finding, name a concrete reader-misled or reader-fatigue scenario; do not flag personal taste.
- Do not use em-dashes in your output. Use commas, parentheses, or two sentences.

# Taxonomy (exactly one category per finding)

| Category | When to use |
|---|---|
| `DOC_DRIFT` | A factual claim in a doc contradicts the current source code (stale signatures, wrong defaults, removed APIs, renamed types, wrong ordering, wrong exception). |
| `STALE_SNIPPET` | A snippet region is missing from its `.dart` file, or the `.dart` file uses an API that no longer exists. |
| `BROKEN_REF` | An internal MDX link (`/concepts/...`, `/reference/...`, `/guides/...`) points to a slug that does not exist, or a class reference (`[ClassName]`) points to something deleted. |
| `MISLEADING` | A claim that is technically defensible but reads as a different thing than it is. |
| `OVERSTATED` | A claim that the package or pattern does more than it actually does. Marketing posing as fact. |
| `REPETITION` | The same point made multiple times in one page or across pages without narrative justification. |
| `REDUNDANT` | A section that adds nothing the reader does not already have from the surrounding text. |
| `QUALITY` | Tone problems, padding, vague hand-waving, undefined jargon, run-on paragraphs that bury the point. Be conservative; only flag what actively obstructs the reader. |
| `PACKAGE_BUG` | The DOC is correct but the SOURCE has the bug. Routes to `PACKAGE_ISSUES.md`, not a doc edit. |

# Output format (strict; the orchestrator parses this verbatim)

First, status:

```
## STATUS
ISSUES_FOUND
```

(or `CLEAN` if you genuinely found zero real issues after sampling at least 8 different files spanning at least 3 of: concepts, reference, guides, READMEs, examples, snippets. If `CLEAN`, stop immediately. Do not pad.)

Then one section per finding:

```
## FINDING F1
- file: <repo-relative path>
- lines: <single line or `42-45` range>
- category: <one of the categories above>
- severity: HIGH | MEDIUM | LOW
- claim: "<the exact phrase or summarized assertion the doc makes>"
- evidence_pointer: <repo-relative source-of-truth path + line range, OR `prose-only` for QUALITY/REDUNDANT findings>
- note: <one sentence of what is wrong; no prose flourishes>
```

Number findings sequentially F1, F2, F3, ... Stop when you reach 15 or when the remaining candidates are LOW severity.

# Done when

You have produced either `STATUS: CLEAN` after broad sampling, or a report containing between 1 and 15 findings, each with a verified file:line claim and a verifiable evidence_pointer. The validator will take it from here.

Begin.
