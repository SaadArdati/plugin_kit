# Goal

Find a public API behavior in the plugin_kit source code that is currently UNTESTED, and propose a characterization test that locks in its present behavior.

# Context

- Working directory: the repo root of `plugin_kit`.
- Current iteration: {{ITERATION}}.
- This loop is the inverse of bug-hunt: we are NOT looking for bugs. We are looking for code paths that lack regression armor. A new test you propose must PASS against the current code; if it doesn't, the test is wrong (or you accidentally found a bug, which belongs in bug-hunt-loop, not here).
- Downstream pipeline: test-writer (writes the characterization test) -> orchestrator runs the test, requires GREEN -> validator (sanity-checks the test shape) -> orchestrator applies a mutation to the cited source and re-runs the test, requires RED (proves the test is load-bearing) -> reviewer (final check that the test is meaningful regression armor).

# Source surface

- `packages/plugin_kit/lib/src/**/*.dart` (pure-Dart core)
- `packages/plugin_kit_dialog/lib/src/**/*.dart` (Flutter dialog)
- `packages/flutter_plugin_kit/lib/src/**/*.dart` (Flutter bridges)

# What "untested" means in this loop

A code path is untested when:

- No existing test file under `packages/{pkg}/test/**/*.dart` exercises the specific assertion you want to make.
- OR: existing tests touch the code path but don't pin the SPECIFIC behavior you've identified (an edge case, a partial-failure path, a concurrent-call interaction, an error message, an observable side effect).

Where to find rich untested areas:

- Partial-failure paths in `runtime.dart`: what happens when one of N plugins throws during a settings reconcile, dispose, attach, detach.
- Concurrent-call interactions: two `updateSettings` calls in flight, dispose-mid-await, createSession during a reconcile.
- Settings normalization edge cases: empty maps, all-wildcards, deeply-nested configs.
- Service-registry priority resolution under combinations of plugin-scoped and wildcard overrides at the same id.
- Event bus dispatch ordering at equal priorities.
- The behavior of `copyWith` and `withClearedPriority` on every state-holding class.
- Exception types thrown from API boundary methods (StateError vs ArgumentError vs PluginLifecycleException).

# Stoplist (DO NOT re-raise; already covered)

{{STOPLIST}}

# Verification commands (use BEFORE proposing)

- Read 2-3 existing test files in the package to understand conventions and ensure you're not duplicating coverage.
- Read the source at the cited file:line range and confirm the behavior you describe is what the code actually does today.
- `rg -n 'SomeMethodName' packages/{pkg}/test/` to verify your target isn't already covered.

# Constraints

- ONE proposal per iteration. Quality over quantity.
- The test must be reproducible by a Dart test alone: no live network, no real Firestore, no platform channels, no flaky golden comparisons.
- The test must PASS against current code. If you suspect the behavior is buggy, this is the WRONG loop; raise it in bug-hunt-loop instead.
- Do not propose tests that pin trivial wrapper behavior (e.g., "constructor stores its argument in a field"). Aim for behavior that an actual refactor could plausibly break.
- The cited source range should be 1-10 lines. Larger ranges mean the test isn't focused enough.
- Do not use em-dashes.

# Taxonomy (exactly one per finding)

| Category | When to use |
|---|---|
| `PARTIAL_FAILURE` | A path where one of multiple steps fails and the runtime must continue / unwind / surface aggregated errors. |
| `CONCURRENT_CALL` | Behavior under interleaved or re-entrant calls to the same API. |
| `EDGE_CASE` | Empty inputs, boundary values, wildcards, max/min, null defaults. |
| `ERROR_TYPE` | Pin which exception type is thrown from which API boundary. |
| `OBSERVABLE_SIDE_EFFECT` | A public-API call has a non-obvious side effect (state change in another field, log emission, stream event) that callers may rely on. |
| `PRIORITY_RESOLUTION` | Specific outcome of registry resolution under a combination of overrides. |
| `LIFECYCLE_ORDER` | The order in which lifecycle hooks fire across plugins and services. |

# Output format (strict; the orchestrator parses this verbatim)

First, status:

```
## STATUS
PROPOSAL_FOUND
```

(or `CLEAN` if after sampling 6+ source files across 2+ packages you cannot find an untested behavior worth pinning.)

Then exactly one proposal:

```
## PROPOSAL

- package: plugin_kit | plugin_kit_dialog | flutter_plugin_kit
- source_file: <repo-relative path under packages/{pkg}/lib/>
- source_lines: <single line or `120-140` range, used as the mutation target>
- category: <one of the categories above>
- behavior: "<one sentence stating the behavior the test will lock in, present tense>"
- repro_strategy: <one or two sentences describing how a Dart test exercises this behavior; what to construct, what to assert>
- why_load_bearing: <one sentence explaining why the cited source lines actually implement this behavior, so mutating them would break the assertion>
- slug: <short-kebab-case identifier>
```

# Done when

You have produced either `STATUS: CLEAN` or exactly one `## PROPOSAL` block with the required fields. The test-writer takes it from there.

Begin.
