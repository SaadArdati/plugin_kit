# Task

Read the staged diff for a decomposition step. Judge whether the diff matches the spec section and whether it is safe to commit.

# Working directory

`/Users/saadardati/IdeaProjects/plugin_kit`

# Context

Step id: `{{STEP_ID}}`
Step title: `{{STEP_TITLE}}`
Cluster label: `{{CLUSTER_LABEL}}`

The spec section for this step lives at `docs/superpowers/plans/2026-05-16-runtime-decomposition.md` lines `{{STEP_START_LINE}}` to `{{STEP_END_LINE}}`. Read it.

The executor's structured report is at `{{EXECUTOR_REPORT_PATH}}`. Read it.

The diff is at `{{DIFF_PATH}}`. Read it. The orchestrator has already gated on `flutter analyze` (zero warnings), `flutter test` (all pass), section-7 grep gates, signature preservation, and line-count delta. Your job is the shape judgment those gates cannot make.

# Decision criteria

PASS the diff when:

1. It matches the spec section exactly: same methods moved, same files touched, same forwarders added. No scope creep (no opportunistic edits to unrelated lines).
2. Forwarder bodies are exactly `=> _<name>Impl(args);`. No additional logic snuck in.
3. Method bodies were moved verbatim. Refactors during the move (renaming locals, reformatting, "improving" loops) are FAIL: this is a pure structural move, behavior must be preserved bit-for-bit.
4. New part files declare `part of '../plugin.dart';` and the part directive is also added to `plugin.dart`.
5. Comments and docstrings on moved methods are preserved unless the spec says otherwise.
6. The naming convention is honored (`*Impl` suffix, `_Runtime<Cluster>` extension type).
7. The cluster label matches one of: dispose pilot, public-api contract test, settings normalizer, enablement resolver, init, session ownership, reconcile.

FAIL the diff when:

1. Methods were edited beyond the move (renamed parameters, simplified bodies, "fixed" log messages).
2. Files outside the step's scope were touched.
3. A forwarder body has any logic beyond the one-line delegation.
4. Public method signatures changed (even cosmetically: type alias, default value change, parameter rename).
5. The spec was not followed: a method the spec said to move is still on `PluginRuntime`, or a method NOT in the spec's move list got moved anyway.
6. Tests were modified except where the step explicitly creates new tests (Step 0a).
7. The diff touches `docs/superpowers/plans/2026-05-16-runtime-decomposition.md` (the spec is read-only).

# Constraints

- Read-only review. Do not edit files. Do not run commands beyond reading the diff and the spec.
- No em-dashes.
- Be specific. Cite file:line in any FAIL reason.

# Output format

```
## DECISION
PASS
```

or

```
## DECISION
FAIL

- violation_1:
  - rule: <one of: scope-creep | forwarder-logic-leak | body-altered | wrong-files | signature-changed | spec-not-followed | spec-edited | tests-edited-wrong | naming-violation | part-of-wrong>
  - cite: <file:line + one sentence describing what is wrong>
- violation_2: ...
```

# Done when

You have output exactly one `## DECISION` block.

Begin.
