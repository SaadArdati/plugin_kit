# Repository Conventions for AI Sub-Agents

This repo is a Dart/Flutter pub workspace. Read `pubspec.yaml` at root for the member list.

## Languages & Toolchains

- Dart SDK `>=3.10.0 <4.0.0`; Flutter `>=3.27.0` for Flutter packages.
- No melos; pure pub workspaces.
- All package commands run from the **package directory**, not the repo root, unless noted otherwise.
- Use `flutter pub get` (not `dart pub get`) for resolution — the workspace contains Flutter members and `dart pub get` cannot resolve workspaces with Flutter SDK deps.

## Test Commands

- Pure-Dart packages (e.g. `packages/plugin_kit`): `flutter test` from the package dir. (Yes, `flutter test` — see toolchain note above.)
- Flutter packages (`packages/plugin_kit_dialog`, `example/code_editor`, `example/plugin_kit_dialog_demo`): `flutter test` from the package dir.
- Golden tests live under `test/goldens/`. Update with `flutter test --update-goldens`. Failure artifacts go to `test/failures/` (gitignored).

## Style

- `dart format .` before every commit. Failure to format is a CI fail.
- `dart analyze` must be clean — including the `public_member_api_docs` lint, which is ENABLED at the workspace level. Every public member of a library package (anything in `lib/` not prefixed with `_`) must have a `///` doc comment. Token-style constants (e.g. `const kAccentBlue = ...`) get a one-line `///` describing what the value represents.
- Doc comments use `///` triple-slash. Library and class docs follow plugin_kit's style: Overview, Lifecycle, Example, See also (where applicable).

## Code Conventions

- File names: `snake_case.dart`. Class names: `UpperCamelCase`.
- One public class per file unless tightly related (e.g., a sealed family).
- Sealed switches must be exhaustive — do not use `default:` in sealed switches; let the analyzer catch new cases.
- Prefer `const` constructors where possible.
- Prefer immutable data classes (final fields, no setters). Use `@immutable` from `package:meta` or `package:flutter/foundation.dart` for documentation.
- Public APIs get `///` doc comments. Package-private (`src/`) types get inline comments only where the *why* is non-obvious.

## Commit Discipline

- One concern per commit. No "various fixes" or "wip".
- Conventional Commits prefix (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- Subject line ≤ 72 chars; body explains *why*, not *what*.
- Always create new commits — never `--amend` or force-push without explicit user permission.
- Co-author tag when AI assistance was used:
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`

## Spec-Driven Implementation

Tasks dispatched to this repo reference a spec section in `docs/superpowers/specs/`. The spec is the source of truth — do not improvise on file paths, type names, behavior, or naming conventions. If a spec section is ambiguous or contradicts the plan task, STOP and report rather than guessing.

## Failure Behavior

If a task's tests fail after your implementation, do NOT edit the spec code or the test to make it pass. STOP and report the failure with the test output verbatim. Plan/spec bugs get fixed by the human, not papered over.

## Touching Files Outside Your Task

Each task lists "Files to create" / "Files to modify" — those are the entire allowed write set. The single exception: a package's public barrel (e.g. `packages/plugin_kit_dialog/lib/plugin_kit_dialog.dart`) may receive added `export '...'` lines when the task instructs you to extend the public API. Never delete or reorder pre-existing exports.
