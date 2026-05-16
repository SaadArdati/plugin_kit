# Task

Execute exactly one step of the runtime decomposition spec. Land code edits in the working tree. Do not commit. Stop when the per-step completion criteria are satisfied or when blocked.

# Working directory

`/Users/saadardati/IdeaProjects/plugin_kit`

# The spec (binding contract)

`docs/superpowers/plans/2026-05-16-runtime-decomposition.md`

Read in full before starting. Section 7 defines the binding per-step completion criteria. Section 9 defines the commit protocol (you will NOT commit; the orchestrator handles staging and the user commits). Section 10 defines rollback. Section 11 defines per-step verification gates.

# This step

Step id: `{{STEP_ID}}`
Step title: `{{STEP_TITLE}}`
Spec section: lines `{{STEP_START_LINE}}` to `{{STEP_END_LINE}}` of the spec file.

Read those exact lines for your instructions. The spec section tells you what methods to move, what file to create, what forwarders to add, what import lines belong where.

# Constraints

- Edit ONLY the files listed in this step's spec section. If the step says "create runtime/dispose.dart and edit runtime.dart and plugin.dart", do not touch anything else.
- Public method signatures on `PluginRuntime` are immutable for this step. If the step adds a forwarder, the forwarder body is exactly `=> _<name>Impl(args);` and the public signature is byte-identical to what it was before.
- Naming: extension implementations use `*Impl` suffix (`_disposeImpl`, `_updateSettingsImpl`, etc.). Private extension types use `_Runtime<Cluster>` pattern (`_RuntimeDispose`, `_RuntimeReconcile`, etc.). Class methods keep their original names. Section 4.x of the spec is binding.
- Part-file URIs: every new file under `lib/src/plugin/runtime/` declares `part of '../plugin.dart';` (with the leading `../`). Verify before saving.
- Imports: for regular libraries (NOT part files) under `lib/src/plugin/runtime/`, sibling imports go `'../../<file>.dart'` (TWO levels up from `runtime/` to reach `lib/src/`). Reaching `plugin.dart` from such a file is FORBIDDEN: it creates a cycle. Use narrowed types (`Set<PluginId>` not `Iterable<Plugin>`) at the collaborator boundary.
- Do NOT commit. Do NOT push. Do NOT git add. The orchestrator stages files after gates pass.
- Do NOT run tests yourself. The orchestrator runs the per-step gates (analyze, test, grep, signatures, reviewer) after you finish. Any test invocation from your sandbox is wasted work and risks environmental flakes (Dart VM aborts, missing toolchains) that lead to spurious BLOCKED reports. If the spec section says "run `flutter test`" as verification, treat that as an INSTRUCTION TO THE ORCHESTRATOR, not to you. Skip it and report DONE.
- Do NOT run `flutter analyze` for the same reason; the orchestrator does it.
- Do NOT modify `docs/superpowers/plans/2026-05-16-runtime-decomposition.md`. The spec is read-only for executors.

# Output

When done, append your structured report to the response. The orchestrator parses this verbatim.

```
## STATUS
DONE | BLOCKED

## FILES MODIFIED
- <relative-path>
- <relative-path>

## FILES ADDED
- <relative-path>

## METHODS MOVED
- <old-location> -> <new-location>

## FORWARDERS ADDED
- <method-signature>

## CLUSTER LABEL
<one of: dispose pilot | public-api contract test | settings normalizer | enablement resolver | init | session ownership | reconcile>

## NOTES
<anything the orchestrator or reviewer should know; one paragraph max>
```

If BLOCKED:

```
## STATUS
BLOCKED

## REASON
<one short paragraph: what went wrong, what you tried, what the spec says, why you cannot proceed>

## SPEC AMBIGUITY (if applicable)
<which spec line is ambiguous and how>
```

# Failure behavior

- If the spec section is internally contradictory or refers to code that does not exist, STOP and report BLOCKED. Do NOT improvise.
- If a forwarder body would need any logic beyond `=> _<name>Impl(args);`, STOP and report BLOCKED.
- If tests are likely to break, finish the edit anyway (the orchestrator will catch it via the test gate), but mention the concern in NOTES.
- Do not edit tests except where the spec explicitly creates new tests (Step 0a deliverables). Editing existing tests to make them pass is a structural failure mode; surface it instead.

# Done when

You have output exactly one `## STATUS` block matching one of the templates above, and (if DONE) the working tree changes match the spec section.

Do not narrate intermediate progress. Do not produce a plan recitation. Begin by reading the spec section, then act.

Begin.
