#!/bin/bash
#
# Optional helper for the Layout Swapper. `omarchy plugin add` installs the
# bar widget; this script wires up the parts a plugin cannot ship on its own.
# Every step asks first (or pass --yes), is idempotent, and backs up any
# config file before appending to it:
#
#   1. symlink bin/omarchy-layout-swapper into ~/.local/bin
#   2. keybinding SUPER + ALT + L -> layout switcher (~/.config/hypr/bindings.lua)
#   3. "Layouts" submenu in the Omarchy menu (~/.config/omarchy/extensions/omarchy-menu.jsonc)
#   4. save-before-shutdown overrides for the System menu entries (same file)
#   5. post-boot hook that restores the last layout after login
#   6. Chromium "Continue where you left off" in every profile (tabs come back)
#   7. take the first snapshot and start the autosave daemon now
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO/bin/omarchy-layout-swapper"
MARK="fans.omarchy.layout-swapper"
YES=0; [[ ${1:-} == --yes ]] && YES=1
ask() { (( YES )) && return 0; read -rp "$1 [y/N] " a; [[ $a == [yY]* ]]; }

chmod +x "$BIN" "$REPO/hooks/layout-swapper" 2>/dev/null || true

# 1. CLI on PATH
if ask "Symlink omarchy-layout-swapper into ~/.local/bin?"; then
  mkdir -p "$HOME/.local/bin"; ln -sfn "$BIN" "$HOME/.local/bin/omarchy-layout-swapper"
  echo "  linked ~/.local/bin/omarchy-layout-swapper"
fi

# 2. Keybinding
B="$HOME/.config/hypr/bindings.lua"
if [[ -f $B ]] && grep -q "$MARK" "$B"; then
  echo "  keybinding already present in $B"
elif ask "Add keybinding SUPER + ALT + L -> Layout switcher to $B?"; then
  [[ -f $B ]] && cp -a "$B" "$B.bak.$(date +%s)"
  cat >>"$B" <<LUA

-- Layout Swapper ($MARK). SUPER + ALT + L was unbound by default.
o.bind("SUPER + ALT + L", "Layout switcher", "$BIN menu switch")
LUA
  echo "  appended; run 'hyprctl reload && hyprctl configerrors' to verify"
fi

# Append a JSONC snippet before the final closing brace of the user menu file.
append_menu() {
  local file=$1 snippet=$2
  mkdir -p "$(dirname "$file")"
  if [[ -f $file ]]; then
    cp -a "$file" "$file.bak.$(date +%s)"
    python3 - "$file" "$snippet" <<'PY'
import sys
path, snippet = sys.argv[1], open(sys.argv[2]).read().rstrip() + "\n"
s = open(path).read()
i = s.rstrip().rfind("}")
if i < 0: sys.exit("no closing brace in " + path)
open(path, "w").write(s[:i] + snippet + s[i:])
PY
  else
    { echo "{"; cat "$snippet"; echo "}"; } >"$file"
  fi
}

# 3. Menu entries
M="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [[ -f $M ]] && grep -q '"layouts"' "$M"; then
  echo "  Layouts submenu already present in $M"
elif ask "Add a Layouts submenu to the Omarchy menu ($M)?"; then
  append_menu "$M" "$REPO/extensions/omarchy-menu.snippet.jsonc"
  echo "  appended; the menu hot-reloads (omarchy menu refresh)"
fi

# 4. Save-before-shutdown overrides
if [[ -f $M ]] && grep -q 'omarchy-layout-swapper save --quiet; omarchy-system-shutdown' "$M"; then
  echo "  System menu overrides already present in $M"
elif ask "Snapshot the layout right before Shutdown/Reboot/Logout from the System menu (overrides those three menu entries)?"; then
  append_menu "$M" "$REPO/extensions/omarchy-menu.system-overrides.jsonc"
  echo "  appended"
fi

# 5. Post-boot hook (restores the last layout after login)
H="$HOME/.config/omarchy/hooks/post-boot.d/layout-swapper"
if [[ -f $H ]] && grep -q "$BIN" "$H"; then
  echo "  post-boot hook already installed at $H"
elif ask "Install the post-boot hook so the last layout comes back after login ($H)?"; then
  tmp=$(mktemp -t layout-swapper.XXXXXX)
  sed "s|@BIN@|$BIN|" "$REPO/hooks/layout-swapper" >"$tmp"
  mv "$tmp" "$tmp.hook"; cp "$tmp.hook" "$(dirname "$tmp")/layout-swapper"
  omarchy-hook-install post-boot "$(dirname "$tmp")/layout-swapper" >/dev/null
  rm -f "$tmp.hook" "$(dirname "$tmp")/layout-swapper"
  echo "  installed $H"
fi

# 6. Chromium: restore tabs on startup. Chromium rewrites Preferences when it
#    exits, so only edit while it is not running.
CHROME_DIR="$HOME/.config/chromium"
if [[ -d $CHROME_DIR ]] && ask "Turn on Chromium's 'Continue where you left off' in every profile (so browser windows come back with their tabs)?"; then
  if pgrep -x chromium >/dev/null || pgrep -f '/usr/lib/chromium/chromium' >/dev/null; then
    echo "  Chromium is running; close it and rerun install.sh, or set chrome://settings/onStartup to 'Continue where you left off' in each profile."
  else
    python3 - "$CHROME_DIR" <<'PY'
import json, os, sys
root = sys.argv[1]
for entry in sorted(os.listdir(root)):
    prefs = os.path.join(root, entry, "Preferences")
    if not (entry == "Default" or entry.startswith("Profile ")) or not os.path.isfile(prefs):
        continue
    try:
        data = json.load(open(prefs, encoding="utf-8"))
    except ValueError:
        print(f"  skipped {entry}: Preferences is not valid JSON"); continue
    session = data.setdefault("session", {})
    if session.get("restore_on_startup") == 1:
        print(f"  {entry}: already set"); continue
    session["restore_on_startup"] = 1
    tmp = prefs + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"), ensure_ascii=False)
    os.replace(tmp, prefs)
    print(f"  {entry}: restore_on_startup = 1")
PY
  fi
fi

# 7. First snapshot + daemon
if ask "Take the first snapshot of the current windows and start the autosave daemon now?"; then
  "$BIN" save || true
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    nohup setsid "$BIN" watch >/dev/null 2>&1 &
    sleep 0.5; "$BIN" status
  else
    echo "  not inside a Hyprland session; the daemon starts from the post-boot hook at next login"
  fi
fi
echo "Done. Enable the bar chip with: omarchy bar add $MARK"
