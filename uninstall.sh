#!/bin/bash
# Undo everything install.sh added: stop the daemon, remove the symlink, the
# keybinding, the menu entries (Layouts submenu and the System overrides),
# and the post-boot hook. Saved layouts under ~/.config/omarchy-layout-swapper
# are kept unless --purge is given. Chromium's startup setting is left alone.
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO/bin/omarchy-layout-swapper"
MARK="fans.omarchy.layout-swapper"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-layout-swapper"

if [[ -f $STATE/watch.pid ]]; then
  kill "$(cat "$STATE/watch.pid")" 2>/dev/null && echo "  stopped autosave daemon" || true
fi

L="$HOME/.local/bin/omarchy-layout-swapper"
[[ -L $L ]] && rm -f "$L" && echo "  removed $L"

B="$HOME/.config/hypr/bindings.lua"
if [[ -f $B ]] && grep -q "$MARK" "$B"; then
  cp -a "$B" "$B.bak.$(date +%s)"
  python3 - "$B" "$MARK" <<'PY'
import sys, re
path, mark = sys.argv[1], sys.argv[2]
s = open(path).read()
s = re.sub(r"\n-- Layout Swapper \(" + re.escape(mark) + r"\)[^\n]*\n[^\n]*\n", "\n", s)
open(path, "w").write(s)
PY
  echo "  removed keybinding from $B"
fi

M="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $M ]] && grep -qE '"layouts(\.[a-z-]+)?"|omarchy-layout-swapper save --quiet' "$M"; then
  cp -a "$M" "$M.bak.$(date +%s)"
  python3 - "$M" <<'PY'
import sys, re
path = sys.argv[1]
lines = open(path).read().split("\n")
keep = []
for line in lines:
    if re.match(r'\s*"layouts(\.[a-z-]+)?"\s*:', line): continue
    if "omarchy-layout-swapper save --quiet" in line: continue
    if "Layout Swapper" in line and line.strip().startswith("//"): continue
    if line.strip().startswith("//") and ("inside ~/.config/omarchy/extensions/omarchy-menu.jsonc" in line or "menu's System entries can be overridden" in line or "desktop tears its windows down" in line): continue
    keep.append(line)
open(path, "w").write("\n".join(keep))
PY
  echo "  removed menu entries from $M"
fi

H="$HOME/.config/omarchy/hooks/post-boot.d/layout-swapper"
[[ -f $H ]] && rm -f "$H" && echo "  removed $H"

if [[ ${1:-} == --purge ]]; then
  rm -rf "$HOME/.config/omarchy-layout-swapper" "$STATE"
  echo "  removed saved layouts and state"
fi
echo "Done. Remove the bar chip with: omarchy bar reset (or edit ~/.config/omarchy/shell.json)"
