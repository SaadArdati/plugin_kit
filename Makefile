# Convenience targets for local development. `make ci` mirrors the
# GitHub Actions workflow in `.github/workflows/ci.yml` so you can
# reproduce CI failures locally before pushing. `make all` adds
# golden-tagged tests on top, which CI skips because PNG rendering
# is environment-sensitive (fonts, sub-pixel positioning).

.PHONY: all ci pub-get analyze test test-goldens doc-check doc-excerpts-check \
        doc-versions-check website-build clean help \
        test-plugin-kit test-plugin-kit-dialog test-flutter-plugin-kit \
        test-snippets test-state-garden test-code-editor \
        test-plugin-kit-dialog-demo \
        doc-audit doc-audit-resume doc-audit-dashboard

# Default target. Run the full CI pipeline AND golden tests.
all: ci test-goldens

# Mirror the GitHub Actions CI workflow.
ci: pub-get analyze test doc-check website-build

# Resolve workspace dependencies once. Every other target assumes this.
pub-get:
	flutter pub get

# --- Analyze ----------------------------------------------------------------

analyze:
	flutter analyze packages/plugin_kit
	flutter analyze packages/plugin_kit_dialog
	flutter analyze packages/flutter_plugin_kit
	flutter analyze website/snippets
	flutter analyze example/state_garden
	flutter analyze example/code_editor
	flutter analyze example/plugin_kit_dialog_demo
	flutter analyze example/model_embassy

# --- Test (no goldens, matches CI) ------------------------------------------

test: test-plugin-kit test-plugin-kit-dialog test-flutter-plugin-kit \
      test-snippets test-state-garden test-plugin-kit-dialog-demo

test-plugin-kit:
	flutter test packages/plugin_kit

test-plugin-kit-dialog:
	flutter test packages/plugin_kit_dialog

test-flutter-plugin-kit:
	flutter test packages/flutter_plugin_kit

test-snippets:
	flutter test website/snippets

test-state-garden:
	flutter test example/state_garden

test-plugin-kit-dialog-demo:
	flutter test example/plugin_kit_dialog_demo --exclude-tags=goldens

# code_editor's tests live alongside golden tests in the same files and
# CI does not run them. Surface them under a dedicated target so the
# golden run picks them up.
test-code-editor:
	flutter test example/code_editor

# --- Goldens ----------------------------------------------------------------

# Golden tests across every package that has them. PNG rendering is
# environment-sensitive; mismatches are likely a font / sub-pixel
# difference between your machine and the goldens' reference machine,
# not a regression. Update locally via:
#   flutter test --update-goldens <test-file>
test-goldens:
	flutter test example/plugin_kit_dialog_demo --tags=goldens
	flutter test example/code_editor

# --- Doc-snippet checks (matches the doc-excerpts CI job) -------------------

doc-check: doc-excerpts-check doc-versions-check

# Verify every Markdown / MDX doc excerpt still matches the source code
# region it points at. This is the check that has been failing in CI.
# To regenerate the excerpts after a code change, run:
#   node scripts/update-md-excerpts.mjs
doc-excerpts-check:
	node scripts/update-md-excerpts.mjs --check

# Verify that pubspec versions referenced inside Markdown install
# snippets match the actual package versions on disk.
doc-versions-check:
	node scripts/sync-md-versions.mjs --check

# --- Website build ----------------------------------------------------------

# Builds the docs site. Compiles every MDX file, which surfaces broken
# excerpt references the doc-excerpts-check might miss (a region whose
# code was deleted, for example). The install / build pair mirrors the
# `doc-excerpts` job in `.github/workflows/ci.yml`. `--frozen-lockfile`
# forces installs to match the committed `website/pnpm-lock.yaml`; if it
# fails, run `pnpm --filter ./website install` to refresh the lockfile
# and commit the result.
website-build:
	pnpm --filter ./website install --frozen-lockfile
	cd website && pnpm build

# --- Helpers ----------------------------------------------------------------

# Regenerate doc excerpts in place (run this after editing a #docregion
# block) so the next `make doc-check` passes.
doc-excerpts-update:
	node scripts/update-md-excerpts.mjs

# Regenerate version pins in install snippets so the next
# `make doc-versions-check` passes.
doc-versions-update:
	node scripts/sync-md-versions.mjs

# --- Doc-audit autonomous loop ----------------------------------------------

# Run the autonomous doc-audit loop: codex agents audit, validate, fix, and
# review the documentation against the source code, gated by an external
# verifier (`make doc-check` + `flutter test website/snippets`). Never commits.
# Default 15-iteration cap; override with `make doc-audit MAX=30`.
DOC_AUDIT_MAX ?= 15
doc-audit:
	bash scripts/doc-audit-loop/orchestrator.sh --max $(DOC_AUDIT_MAX)

# Resume the most recent doc-audit run from where it left off. Reuses the
# accumulated stoplist and iteration counter; safe after a crash.
doc-audit-resume:
	bash scripts/doc-audit-loop/orchestrator.sh \
		--resume "$$(cd scripts/doc-audit-loop/runs/latest && pwd -P)" \
		--max $(DOC_AUDIT_MAX)

# Launch the live monitoring dashboard for the latest doc-audit run. Installs
# Vite deps on first run, then starts the dev server on http://localhost:4322.
doc-audit-dashboard:
	cd scripts/doc-audit-loop/dashboard && \
		[ -d node_modules ] || npm install && \
		npm run dev

clean:
	flutter clean
	find packages example website -type d -name .dart_tool -prune -exec rm -rf {} +
	find packages example website -type d -name build -prune -exec rm -rf {} +

help:
	@echo "Targets:"
	@echo "  make            Full CI pipeline plus golden tests (alias for 'all')."
	@echo "  make ci         Mirror the GitHub Actions CI workflow."
	@echo "  make analyze    Run flutter analyze across every package."
	@echo "  make test       Run every package's tests, skipping goldens (matches CI)."
	@echo "  make test-goldens   Run only the golden-tagged tests."
	@echo "  make doc-check  Verify doc excerpts and install versions are in sync."
	@echo "  make doc-excerpts-update   Regenerate doc excerpts in place."
	@echo "  make doc-versions-update   Regenerate install version pins."
	@echo "  make website-build   Install website deps and build the static site."
	@echo "  make doc-audit       Run the autonomous doc-audit loop (codex agents)."
	@echo "  make doc-audit-resume   Resume the most recent doc-audit run."
	@echo "  make doc-audit-dashboard   Start the live monitoring dashboard at :4322."
	@echo "  make clean      Remove .dart_tool / build dirs."
