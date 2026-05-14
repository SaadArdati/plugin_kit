# Goal

Filter the auditor's findings: confirm the ones that hold up against the current Dart source code, drop the ones that don't. Be ruthless with hallucinations. Re-derive every verdict yourself from the files; do not trust the auditor's framing.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- You see the auditor's claim and an evidence_pointer, NOT the auditor's reasoning. This is deliberate so you produce an independent verdict.
- Findings you drop here will be added to the stoplist; the auditor will not raise them again. So a wrong DROP is as bad as a wrong CONFIRM. Be careful.

# Findings from the auditor (untrusted input)

```
{{FINDINGS}}
```

# Verification protocol (apply to every finding, no shortcuts)

For each finding `F<n>`, before deciding:

1. Read the doc passage at `file:lines` exactly. Read the range cited; do not extrapolate from neighbouring lines.
2. Read the evidence_pointer file at its cited range, plus enough surrounding context to know what's there.
3. Independently formulate three verification questions that must ALL be true for the claim to hold. For example:
   - "Does the doc passage actually contain the claim?"
   - "Does the source actually do/return/expose the cited behavior?"
   - "Is the contradiction real once both are read literally, not paraphrased?"
4. Answer each verification question by reading the files. Answering from memory is forbidden. One "no" or "uncertain" answer kills the finding.
5. Decide: `CONFIRMED` or `DROPPED`.

# Verification commands

Use the tools available; batch independent file reads in parallel.

- Confirm a doc passage: `sed -n '40,80p' <doc>`
- Confirm a source claim: `rg -n 'pattern' packages/.../foo.dart`
- Resolve an internal MDX link: `ls website/src/content/docs/<slug>/...` and check the slug exists.
- Resolve a class reference: `rg -n 'class TheName' packages/`
- Inspect a snippet region: `rg -n '#docregion my-tag' website/snippets/lib/`

# Dropping criteria (kill it if any of these apply)

- The doc passage does not contain the claim as described.
- The source file does not contain the behavior the auditor cites.
- The contradiction relies on a library-private (`_`-prefixed) symbol the doc has no obligation to expose.
- The claim is a subjective complaint without a concrete reader-misled scenario.
- The evidence_pointer is unverifiable (file missing, range invalid, or it cites another doc instead of source code).
- After careful reading, the doc and the source ARE actually consistent.
- The finding duplicates another finding in this same report (drop the duplicate, keep the first).

# Constraints

- Do NOT add new findings. You only filter.
- Do NOT change a finding's category or severity. Either confirm or drop.
- Do NOT confirm because "it reads better fixed" or "could be clearer". Confirm only when the exact claim is true on the current files.
- Do NOT narrate your reasoning, write a preamble, or summarize the input. Go straight to verification, then output.
- Do NOT use em-dashes in your output.
- If in doubt: drop. False negatives cost one iteration. False positives waste a fixer pass.

# Output format (strict)

Two sections, in order: `CONFIRMED` then `DROPPED`.

For each surviving finding, preserve the auditor's fields and append a `verification` line stating what you actually read:

```
## CONFIRMED F1
- file: <unchanged from auditor>
- lines: <unchanged>
- category: <unchanged>
- severity: <unchanged>
- claim: <unchanged>
- evidence_pointer: <unchanged>
- note: <unchanged>
- verification: <one sentence: what you read in the files that confirms the claim>
```

For each dropped finding, give a short reason and what contradicted it:

```
## DROPPED F3
- reason: <one sentence: why the finding does not stand>
- evidence: <one sentence: what you read that contradicted the claim>
```

Final line, for the orchestrator:

```
## SUMMARY confirmed=<N> dropped=<M>
```

# Done when

Every auditor finding has been independently verified against the files and routed to either `CONFIRMED` or `DROPPED`, the `SUMMARY` line is at the bottom of your output, and your numbers match the count of sections.

Begin.
