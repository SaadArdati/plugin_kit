# Goal

Verify the iteration honored TDD discipline AND did not introduce flutter-architecture violations. Output PASS or FAIL with cited evidence.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- The orchestrator has already performed machine checks (red timestamp < green timestamp, test file byte-unchanged between RED and GREEN, lib/ diff non-empty, no other tests regressed). If any of those failed, you would not be reading this prompt; the iteration would already be rolled back.
- Your remaining job: catch the things the orchestrator's mechanical checks cannot see.

# Inputs

Package: `{{PACKAGE}}`

Test file (unchanged between RED and GREEN; the orchestrator already verified this):

`{{TEST_FILE_PATH}}`

Production-code diff (this is what the fixer changed):

`{{DIFF_PATH}}`

Fixer report:

```
{{FIX_REPORT}}
```

RED output excerpt (proof the test failed before the fix):

```
{{RED_OUTPUT}}
```

GREEN output excerpt (proof the test passes now AND no other tests broke):

```
{{GREEN_OUTPUT}}
```

# Verification commands

- Read the diff file at `{{DIFF_PATH}}` line by line. Every changed line must serve the test's pass condition.
- For each edited file, read its full current contents at the cited lines. Then check the scope-aware architecture rules below.
- Grep call sites of any method whose signature changed: `rg -n 'method_name' packages/ example/ website/snippets/`. If callers are broken, the green output would already show it, but you still verify by reading.

# TDD discipline checks (still your job; not all mechanizable)

1. The fixer's `## ROOT_CAUSE` sentence must describe a real defect, not a missing feature. (TDD does not turn missing features into bugs.)
2. The fixer's edit must not add a workaround that masks the bug elsewhere (e.g. catching the exception and ignoring it rather than fixing the offending code).
3. The diff must not add code that has no corresponding test assertion. "Defensive" additions ("just in case the user does X") are over-engineering; reject them.
4. The diff must not include unrelated refactoring. "Cleaned up while I was here" is grounds for FAIL.

# flutter-architecture rules (scope-aware)

Apply these rules to every changed file under `{{PACKAGE}}/lib/`:

### Always-apply (all packages)

- **CRITICAL-3** One state holder = one concern. If the fix bundled unrelated responsibilities into one class, FAIL.
- **CRITICAL-5** Depend on abstract interfaces, not concrete types. If the fix added a `final HttpFooRepo _repo` field instead of `final AbstractFooRepo _repo`, FAIL.
- **CRITICAL-8** State holders communicate through call sites / contexts, not direct sibling references. If the fix wired `final OtherHolder _other` into a class, FAIL.
- **CRITICAL-9** Typed identifiers, not raw strings. If the fix introduced `'my_plugin'` instead of `PluginId('my_plugin')`, or hard-coded a route/storage key as a raw string, FAIL.

### Apply only for `plugin_kit_dialog` and `flutter_plugin_kit`

- **CRITICAL-1** Every `Loading()` / `Failure()` carries `data: currentData`. If the fix introduced a state holder that drops the user's data on loading, FAIL.
- **CRITICAL-2** Every `async` method checks `if (disposed) return` / `if (isClosed) return` / `if (!mounted) return` after every `await`. If the fix introduced a new `async` method that omits this check, FAIL.
- **CRITICAL-4** No `default:` on a `switch` over a sealed type or enum. If the fix introduced one, FAIL.
- **CRITICAL-6** Never a blank screen. Cached data, skeleton, or empty-state message. If the fix introduced a UI path that renders nothing on Loading or Failure, FAIL.
- **CRITICAL-7** Side effects in listeners, UI in builders. If the fix introduced `Navigator.push(...)` or analytics inside a `build()` body, FAIL.
- **CRITICAL-10** Exposed state types support value equality. If the fix introduced a new state class without `EquatableMixin` or equivalent, FAIL.

# Testing anti-patterns (TDD skill)

- Adding test-only methods to production classes (e.g. `@visibleForTesting` accessors purely to make the test assertable) is a smell; FAIL unless there is no other way.
- Production code referencing `Platform.environment['DART_TEST']` or similar test detection is FAIL.
- Production code changing behavior when `runtimeType.toString().contains('Mock')` is FAIL.

# Lint hygiene (codex agents must clean up after themselves)

After reading the diff, run `dart analyze packages/{{PACKAGE}}/lib` (or `flutter analyze packages/{{PACKAGE}}/lib`). If your reading of the output shows the fixer's diff introduced any NEW analyzer findings (error / warning / info / lint) at the changed lines, FAIL the iteration. Pre-existing findings unrelated to the diff are not your concern. Cite the analyzer line verbatim in the violation block.

Also FAIL on:

- Any new `// ignore:` or `// ignore_for_file:` comment in the diff. Suppressing lints is not fixing the bug; it is hiding it.
- Hyphens in any Dart filename under the diff (`file_names` lint will flag them, and the orchestrator's bug-hunt test path convention is snake_case).
- New files outside the documented allowed surfaces (`packages/{{PACKAGE}}/lib/` plus the test file the fixer is forbidden from touching).

# Constraints

- Read every file in the diff. Do not skim. A 20-line diff that looks innocuous can hide a CRITICAL violation.
- FAIL with a single specific cite (file:line + which rule). If multiple violations, list each. Cite the rule by id (`CRITICAL-2`, etc.) where applicable.
- Do not propose fixes. Do not edit anything. You are read-only.
- Do not narrate or write a preamble. Do not use em-dashes.

# Output format (strict; the orchestrator parses this verbatim)

```
## DECISION
PASS
```

or

```
## DECISION
FAIL

- violation_1:
  - rule: <CRITICAL-N | TDD-rationalization | unrelated-refactor | masked-bug | other>
  - file: <repo-relative path>
  - line: <line number or range>
  - cite: <one sentence describing what is wrong; reference specific code>
- violation_2: ...
```

# Done when

You have output exactly one `## DECISION` block. PASS means the diff is keepable. FAIL means the orchestrator restores the lib/ snapshot, wraps the failing test in `@Skip(...)`, and appends an entry to PACKAGE_ISSUES.md.

Begin.
