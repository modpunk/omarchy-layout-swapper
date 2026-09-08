#!/bin/bash
# The bar widget builds its command as
#   $(if command -v omarchy-layout-swapper ...; then echo omarchy-layout-swapper; else echo '<plugin bin>'; fi) <args>
# and hands it to bar.run (bash -lc). Check both branches of that expression
# resolve to a runnable CLI. Uses this checkout's bin as the "plugin copy".
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="$ROOT/bin/omarchy-layout-swapper"
export LAYOUT_SWAPPER_CONFIG_DIR="${TMPDIR:-/tmp}/lsw-widget-$$" LAYOUT_SWAPPER_STATE_DIR="${TMPDIR:-/tmp}/lsw-widget-$$/state"
trap 'rm -rf "$LAYOUT_SWAPPER_CONFIG_DIR"' EXIT

out=$($(if command -v omarchy-layout-swapper >/dev/null 2>&1; then echo omarchy-layout-swapper; else echo "$PLUGIN"; fi) status --short)
[[ $out == main ]] || { echo "  FAIL on-PATH branch: $out"; exit 1; }
echo "  ok   widget command (PATH branch or plugin fallback): $out"

out=$($(if command -v no-such-cli-xyz >/dev/null 2>&1; then echo no-such-cli-xyz; else echo "$PLUGIN"; fi) status --short)
[[ $out == main ]] || { echo "  FAIL fallback branch: $out"; exit 1; }
echo "  ok   widget command (forced fallback): $out"
