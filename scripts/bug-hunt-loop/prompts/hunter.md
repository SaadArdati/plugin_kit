# Goal

Hypothesize ONE real, reproducible bug in the plugin_kit source code. Output a single finding the test-writer can turn into a failing test.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- The downstream pipeline is: test-writer (writes a failing test) -> orchestrator runs `dart test` and captures RED output -> validator (drops weak hypotheses) -> fixer (minimal edit to make test pass) -> reviewer (TDD discipline + architecture rules) -> orchestrator runs full test suite for GREEN.
- Your job ends at producing the hypothesis. Do not write tests, do not edit source, do not propose fixes.

# Source surface (where bugs live)

- `packages/plugin_kit/lib/src/**/*.dart` (pure-Dart core: registry, runtime, settings, event bus, plugin lifecycle, sessions, exceptions)
- `packages/plugin_kit_dialog/lib/src/**/*.dart` (Flutter dialog widget + controller + visuals plugin)
- `packages/flutter_plugin_kit/lib/src/**/*.dart` (Flutter bridges: session listener, event notifier, session events mixin)

Existing tests live under each package's `test/` directory. Bug-hunt tests written by this loop are at `packages/{pkg}/test/bug_hunt/`.

# Where bugs cluster (prioritize sampling here)

- Async ordering and partial-failure paths: `runtime.dart` (settings updates, session reconciliation, rollback), `_runAttach` / `_runDetach`, `updateSettings`, `updateSessionSettings`.
- Resource lifecycle: subscription tracking in `StatefulPluginService.attach/detach`, `PluginHelper.on`/`bind`/`onRequest`, leak detection on re-bind during cancel.
- Sealed-type exhaustiveness in `plugin_kit_dialog` state classes and any `switch` over sealed/enum types.
- Settings cascade: wildcard overrides vs plugin-scoped overrides, locked plugins, feature flag fallthrough.
- Event bus edge cases: `stop()` propagation, identifier-scoped vs global handler ordering at equal priority, request handler returning null when next should run.
- Equality and copyWith correctness: `RegistrationWrapper` equality, `RuntimeSettings.copyWith`, `ConfigNode` coercion accessors.
- Disposal safety: `if (disposed) return` after every `await` in Flutter bridges (state holders); the dispose vs in-flight await race.
- Error rollback: `updateSettings` rollback is documented as best-effort - find a path where rollback silently corrupts state.

# Stoplist (DO NOT re-raise; already covered by a prior iter)

{{STOPLIST}}

# Open package issues (DO NOT rediscover; already filed)

These bugs are already known and tracked in `PACKAGE_ISSUES.md`. They are still OPEN (not yet fixed), but a separate workflow handles them. Your job is to find DIFFERENT bugs. Treat each entry below as if it were on the stoplist: do not raise the same slug, and do not raise a bug at the same `source file:line` that another OPEN issue already names.

{{OPEN_ISSUES}}

# Verification commands (use BEFORE flagging)

Codex produces better hunts when it grounds claims in actual code. Batch independent reads in parallel.

- Find a symbol: `rg -n 'class FooBar|FooBar\\(' packages/`
- Find every call site: `rg -n 'foo\\.bar\\(' packages/ example/ website/snippets/`
- Read a specific code region: `sed -n '120,180p' packages/plugin_kit/lib/src/plugin/runtime.dart`
- Check existing test coverage for a method: `rg -n 'updateSettings' packages/plugin_kit/test/`
- Check the bug-hunt test dir for prior reproducers: `ls packages/*/test/bug_hunt/ 2>/dev/null`

If you cannot read the actual failure mode in the source code, do NOT flag.

# Constraints

- ONE finding per iteration. Pick the highest-impact reproducible bug you can name with file:line evidence. Quality over quantity.
- Read at least 2 source files before flagging. Never flag from documentation or memory.
- The bug must be reproducible by a Dart test alone: pure code paths, no live network, no real Firestore, no Flutter golden tests, no platform channels. If the bug requires GUI interaction or a real backend, do NOT flag (the loop cannot test it).
- The bug must be a real defect (incorrect behavior, leak, race, exception swallowed, etc.), not a code-smell or refactor opportunity. Architectural critique belongs in a separate planning task.
- Do not propose a fix. Do not write the test. Do not narrate. Output the finding only.
- Do not flag anything in the stoplist, even to explain why you skipped it.
- Do not use em-dashes.

# Taxonomy (exactly one per finding)

| Category | When to use |
|---|---|
| `LEAK` | A resource (subscription, listener, timer, controller) is registered but the cancel/dispose path is missing or unreachable. |
| `RACE` | A code path produces wrong state when two async operations interleave (concurrent settings updates, dispose mid-await, etc.). |
| `ROLLBACK_GAP` | An error-recovery path fails to restore prior state, leaving the runtime in an inconsistent state. |
| `WRONG_ORDER` | Operations execute in an order that contradicts the documented contract (e.g. `detach` after services tear down when docs say before). |
| `MISSING_GUARD` | An invariant is asserted in one path but not in a symmetric path that should also enforce it. |
| `EXHAUSTIVENESS` | A `switch` on a sealed/enum type has `default:` or omits a variant, hiding bugs when the type grows. |
| `EQUALITY` | A value class is missing `==`/`hashCode` or has incorrect props, causing spurious rebuilds or false cache misses. |
| `EXCEPTION_SWALLOWED` | An error is caught and logged or silently dropped where the contract requires it propagate. |
| `WRONG_RETURN` | A method returns the wrong value on an edge case (null when documented non-null, empty when there is data, etc.). |
| `STATE_CORRUPTION` | Mutable state is shared, aliased, or mutated through a returned reference in a way that breaks isolation. |

# Output format (strict; the orchestrator parses this verbatim)

First, status:

```
## STATUS
HYPOTHESIS_FOUND
```

(or `CLEAN` if after sampling at least 6 source files spanning at least 2 of the three packages you cannot ground a single bug. If `CLEAN`, stop immediately. Do not pad.)

Then exactly one finding section:

```
## HYPOTHESIS

- package: plugin_kit | plugin_kit_dialog | flutter_plugin_kit
- file: <repo-relative path under packages/{pkg}/lib/>
- lines: <single line or `120-140` range>
- category: <one of the categories above>
- severity: HIGH | MEDIUM | LOW
- bug: "<one sentence stating the incorrect behavior, present tense>"
- repro_strategy: <one sentence describing how a Dart test could trigger this; what to construct, what to await, what assertion fails>
- expected: "<what the code should do>"
- actual: "<what the code does instead, with file:line citation>"
- evidence: <list of file:line citations in the source code that prove the bug exists; minimum 2>
- slug: <short-kebab-case identifier, used for the test filename and PACKAGE_ISSUE id>
```

# Done when

You have produced either `STATUS: CLEAN` after broad sampling, or a report containing exactly one HYPOTHESIS with a verified file:line bug and a credible repro_strategy under 5 lines of test code. The test-writer takes it from here.

Begin.
