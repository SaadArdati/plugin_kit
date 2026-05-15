#!/usr/bin/env bash
# Thin wrapper around triage.py. Triage parses, verifies, re-keys, and
# rewrites PACKAGE_ISSUES.md against the current code.
#
# Usage:
#   bash scripts/bug-hunt-loop/triage.sh
#   bash scripts/bug-hunt-loop/triage.sh --dry-run
#   bash scripts/bug-hunt-loop/triage.sh --verbose

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/triage.py" "$@"
