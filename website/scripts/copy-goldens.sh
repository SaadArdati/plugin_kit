#!/usr/bin/env bash
# Copies golden images from the plugin_kit_dialog_demo test suite into the
# website's public assets so they can be embedded in MDX as `/images/...`.
#
# Goldens are the single source of truth: regenerate them with
#   flutter test --update-goldens example/plugin_kit_dialog_demo/test/golden_test.dart
# Then run this script (or `npm run build` / `npm run dev`) to refresh assets.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBSITE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$WEBSITE_DIR/.." && pwd)"

SRC="$REPO_ROOT/example/plugin_kit_dialog_demo/test/goldens"
DST="$WEBSITE_DIR/public/images/dialog"

if [[ ! -d "$SRC" ]]; then
  echo "copy-goldens: source dir not found: $SRC" >&2
  exit 1
fi

mkdir -p "$DST"
# Drop any stale copies so renamed/removed goldens do not linger in the website.
rm -f "$DST"/*.png

count=0
for png in "$SRC"/*.png; do
  [[ -e "$png" ]] || continue
  cp "$png" "$DST/"
  count=$((count + 1))
done

if [[ "$count" -eq 0 ]]; then
  echo "copy-goldens: no .png files in $SRC" >&2
  exit 1
fi

echo "copy-goldens: copied $count file(s) to $DST"
