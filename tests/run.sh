#!/bin/bash
# Offline tests: drive bin/omarchy-layout-swapper against a fake compositor
# (JSON fixtures + a dispatch log instead of hyprctl), a fake /proc tree, and
# a fake Hyprland event socket. Needs bash, python3, jq.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
L="$ROOT/bin/omarchy-layout-swapper"
T=$(mktemp -d); trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null || true' EXIT
export LAYOUT_SWAPPER_CONFIG_DIR="$T/config" LAYOUT_SWAPPER_STATE_DIR="$T/state"
export LAYOUT_SWAPPER_FAKE_DIR="$T/fake" LAYOUT_SWAPPER_PROC="$T/proc"
export LAYOUT_SWAPPER_APPS_DIRS="$T/apps" LAYOUT_SWAPPER_BINDINGS="$T/bindings.lua"
mkdir -p "$T/fake" "$T/apps"
pass() { echo "  ok   $*"; }
tfail() {
  echo "  FAIL $*"
  for f in "$T/fake/dispatch.log" "$T"/*.out "$T/state/watch.log"; do
    [[ -f $f ]] && { echo "  --- $(basename "$f") ---"; cat "$f"; }
  done
  exit 1
}

# ---- fixtures: fake /proc, desktop files, bindings
python3 - "$T" <<'PY'
import os, sys
T = sys.argv[1]
def proc(pid, ppid, argv, exe, cwd, pgrp=None, tpgid=None):
    d = os.path.join(T, "proc", str(pid)); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "cmdline"), "wb").write(b"\0".join(a.encode() for a in argv) + b"\0")
    open(os.path.join(d, "exe"), "w").write(exe)
    open(os.path.join(d, "cwd"), "w").write(cwd)
    pgrp = pgrp or pid; tpgid = tpgid or pgrp
    # pid (comm) state ppid pgrp session tty tpgid ...
    open(os.path.join(d, "stat"), "w").write(f"{pid} ({os.path.basename(exe)[:15]}) S {ppid} {pgrp} {pgrp} 34816 {tpgid} 0 0\n")
proc(15035, 1, ["/usr/lib/chromium/chromium", "--ozone-platform=wayland"], "/usr/lib/chromium/chromium", "/home/u")
proc(19285, 1, ["foot", "--app-id=org.omarchy.agent", "-e", "claude", "--permission-mode", "auto"], "/usr/bin/foot", "/")
proc(19304, 19285, ["/home/u/.local/share/mise/installs/claude/latest/claude", "--permission-mode", "auto"], "/home/u/.local/share/mise/installs/claude/latest/claude", "/home/u/Work")
proc(30000, 1, ["foot"], "/usr/bin/foot", "/home/u")
proc(30001, 30000, ["bash"], "/usr/bin/bash", "/home/u/Work/tries", pgrp=30001, tpgid=30002)   # nvim in the foreground
proc(30002, 30001, ["nvim", "notes.md"], "/usr/bin/nvim", "/home/u/Work/tries", pgrp=30002)
proc(31000, 1, ["alacritty"], "/usr/bin/alacritty", "/home/u")
proc(31001, 31000, ["bash", "-c", "tmux attach || tmux new -s Work"], "/usr/bin/bash", "/home/u")
proc(31002, 31001, ["tmux", "attach"], "/usr/bin/tmux", "/home/u")
proc(32000, 1, ["foot"], "/usr/bin/foot", "/home/u")
proc(32001, 32000, ["zsh"], "/usr/bin/zsh", "/home/u/Work", pgrp=32001)                        # idle shell
proc(44721, 1, ["/usr/bin/aether"], "/usr/bin/aether", "/home/u")
proc(194829, 1, ["/usr/bin/nautilus", "--new-window"], "/usr/bin/nautilus", "/home/u")
os.makedirs(os.path.join(T, "apps"), exist_ok=True)
open(os.path.join(T, "apps", "Discord.desktop"), "w").write("[Desktop Entry]\nName=Discord\nExec=omarchy-launch-webapp https://discord.com/channels/@me\nType=Application\n")
open(os.path.join(T, "apps", "X.desktop"), "w").write("[Desktop Entry]\nName=X\nExec=omarchy-launch-webapp https://x.com/\nType=Application\n")
open(os.path.join(T, "bindings.lua"), "w").write('o.bind("SUPER+SHIFT+CTRL+G", "Grok", { webapp = "https://grok.com" })\n')
PY

cat >"$T/fake/monitors.json" <<'J'
[{"id":0,"name":"eDP-1"}]
J
echo '{"id":3,"name":"3"}' >"$T/fake/activeworkspace.json"
mkwin() { # addr class title ws pid stableId at size floating pinned fullscreen
  jq -cn --arg a "$1" --arg c "$2" --arg t "$3" --arg w "$4" --argjson p "$5" --arg s "$6" --argjson at "$7" --argjson sz "$8" --argjson f "$9" --argjson pin "${10}" --argjson fs "${11}" \
    '{address:$a,mapped:true,hidden:false,class:$c,initialClass:$c,title:$t,initialTitle:$t,workspace:{id:($w|tonumber? // -98),name:$w},pid:$p,stableId:$s,at:$at,size:$sz,floating:$f,pinned:$pin,fullscreen:$fs,monitor:0,focusHistoryID:1}'
}
{
  mkwin 0x1 chrome-x.com__-Profile_1 "Home / X" 1 15035 s1 '[12,38]' '[1256,750]' false false 0
  mkwin 0x2 chrome-grok.com__-Default Grok 2 15035 s2 '[647,38]' '[621,750]' false false 0
  mkwin 0x3 chrome-discord.com__channels__me-Default Discord 2 15035 s3 '[12,38]' '[621,750]' false false 0
  mkwin 0x4 chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2 App 5 15035 s4 '[12,38]' '[621,750]' false false 0
  mkwin 0x5 chromium "Docs - Chromium" 4 15035 s5 '[12,38]' '[621,750]' false false 0
  mkwin 0x6 chromium "Mail - Chromium" 4 15035 s6 '[647,38]' '[621,750]' false false 0
  mkwin 0x7 org.omarchy.agent "◑ session persistence" 3 19285 s7 '[12,38]' '[1256,750]' false false 0
  mkwin 0x8 foot "nvim notes.md" 3 30000 s8 '[100,100]' '[800,500]' true true 0
  mkwin 0x9 Alacritty tmux 6 31000 s9 '[12,38]' '[1256,750]' false false 0
  mkwin 0xa foot zsh 6 32000 s10 '[12,38]' '[1256,750]' false false 2
  mkwin 0xb Aether Aether 2 44721 s11 '[12,38]' '[621,750]' false false 0
  mkwin 0xc org.gnome.Nautilus logos special:scratchpad 194829 s12 '[12,38]' '[621,750]' false false 0
  mkwin 0xd org.omarchy.menu menu 3 99 s13 '[0,0]' '[1,1]' true false 0
  mkwin 0xe foot parked special:ls-other 32000 s14 '[0,0]' '[1,1]' false false 0
} | jq -s . >"$T/fake/clients.json"

echo "== save: launch derivation"
"$L" save main >/dev/null || tfail "save exited non-zero"
J="$T/config/layouts/main.json"
[[ -f $J ]] || tfail "layout file missing"
n=$(jq '.windows|length' "$J"); [[ $n == 12 ]] || tfail "expected 12 windows (menu + parked ignored), got $n"
kind() { jq -r --arg c "$1" '.windows[]|select(.class==$c)|.launch.kind' "$J" | head -1; }
cmd() { jq -r --arg c "$1" '.windows[]|select(.class==$c)|.launch.cmd' "$J" | head -1; }
[[ $(kind chrome-x.com__-Profile_1) == webapp ]] || tfail "webapp kind"
[[ $(cmd chrome-x.com__-Profile_1) == "omarchy-launch-webapp https://x.com/ --profile-directory='Profile 1'" ]] || tfail "webapp cmd: $(cmd chrome-x.com__-Profile_1)"
[[ $(cmd chrome-grok.com__-Default) == "omarchy-launch-webapp https://grok.com --profile-directory=Default" ]] || tfail "webapp from bindings: $(cmd chrome-grok.com__-Default)"
[[ $(cmd chrome-discord.com__channels__me-Default) == "omarchy-launch-webapp https://discord.com/channels/@me --profile-directory=Default" ]] || tfail "webapp with path: $(cmd chrome-discord.com__channels__me-Default)"
[[ $(kind chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2) == pwa ]] || tfail "pwa kind"
[[ $(cmd chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2) == "chromium --profile-directory='Profile 2' --app-id=pacgdjiidkfdhilcljkeebfoklekebig" ]] || tfail "pwa cmd: $(cmd chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2)"
[[ $(kind chromium) == chromium && $(cmd chromium) == "chromium --new-window" ]] || tfail "chromium: $(cmd chromium)"
[[ $(kind org.omarchy.agent) == agent ]] || tfail "agent kind"
[[ $(cmd org.omarchy.agent) == "xdg-terminal-exec --app-id=org.omarchy.agent --dir=/home/u/Work -e /home/u/.local/share/mise/installs/claude/latest/claude --permission-mode auto" ]] || tfail "agent cmd: $(cmd org.omarchy.agent)"
[[ $(cmd foot) == "xdg-terminal-exec --app-id=foot --dir=/home/u/Work/tries -e bash -c 'nvim notes.md; exec bash'" ]] || tfail "foreground job: $(cmd foot)"
[[ $(kind Alacritty) == tmux && $(cmd Alacritty) == "xdg-terminal-exec --app-id=Alacritty --dir=/home/u -e bash -c 'tmux attach || tmux new -s Work'" ]] || tfail "tmux: $(cmd Alacritty)"
idle=$(jq -r '.windows[]|select(.class=="foot" and .title=="zsh")|.launch.cmd' "$J")
[[ $idle == "xdg-terminal-exec --app-id=foot --dir=/home/u/Work" ]] || tfail "idle shell: $idle"
[[ $(kind Aether) == native && $(cmd Aether) == "/usr/bin/aether" ]] || tfail "native: $(cmd Aether)"
[[ $(jq -r '.windows[]|select(.class=="Aether")|.launch.cwd' "$J") == /home/u ]] || tfail "native cwd"
[[ $(cmd org.gnome.Nautilus) == "/usr/bin/nautilus --new-window" ]] || tfail "nautilus"
[[ $(jq -r '.windows[]|select(.class=="org.gnome.Nautilus")|.workspace' "$J") == special:scratchpad ]] || tfail "scratchpad kept"
[[ $(jq -r '.windows[]|select(.title=="nvim notes.md")|[.floating,.pinned,.size[0]]|@csv' "$J") == "true,true,800" ]] || tfail "float/pin/size"
[[ $(jq -r '.windows[]|select(.title=="zsh")|.fullscreen' "$J") == 2 ]] || tfail "fullscreen int"
[[ $(jq -r '.active_workspace' "$J") == 3 && $(jq -r '.monitors[0]' "$J") == eDP-1 ]] || tfail "meta"
[[ $(cat "$T/state/active") == main ]] || tfail "active set"
pass "12 records, every launch kind derived as expected"

echo "== save: empty snapshot refused, --force allowed"
cp "$T/fake/clients.json" "$T/clients.full.json"; echo '[]' >"$T/fake/clients.json"
if "$L" save main 2>/dev/null; then tfail "empty save should fail"; fi
[[ $(jq '.windows|length' "$J") == 12 ]] || tfail "layout clobbered"
"$L" save main --force >/dev/null; [[ $(jq '.windows|length' "$J") == 0 ]] || tfail "--force"
cp "$T/clients.full.json" "$T/fake/clients.json"; "$L" save main >/dev/null
pass "refusal and --force"

echo "== backups rotate (max 5)"
for i in 1 2 3 4 5 6 7; do
  jq --arg t "title $i" '.[4].title=$t' "$T/clients.full.json" >"$T/fake/clients.json"; "$L" save main >/dev/null; sleep 1
done
b=$(ls "$T/state/backups"/main.*.json | wc -l); [[ $b -le 5 && $b -ge 4 ]] || tfail "backups: $b"
cp "$T/clients.full.json" "$T/fake/clients.json"; "$L" save main >/dev/null
pass "backup count $b"

echo "== list / show / rename / delete / status"
"$L" save alt --no-activate >/dev/null
[[ $(cat "$T/state/active") == main ]] || tfail "--no-activate"
"$L" list | grep -q '^\* main' || tfail "list marks active"
"$L" show alt | grep -q 'ws 3 ' || tfail "show"
"$L" rename alt alt2 >/dev/null; [[ -f $T/config/layouts/alt2.json ]] || tfail "rename"
if "$L" delete main 2>/dev/null; then tfail "deleting active should fail"; fi
"$L" delete alt2 >/dev/null; [[ ! -f $T/config/layouts/alt2.json ]] || tfail "delete"
"$L" status --json | jq -e '.active=="main" and .boot=="auto" and (.watch_pid==null)' >/dev/null || tfail "status json"
"$L" config boot ask; [[ $("$L" config boot) == '"ask"' ]] || tfail "config set"; "$L" config boot auto
pass "management commands"

echo "== restore: claim existing, launch missing, place, chromium bootstrap"
# Live desktop: X webapp (same stableId, moved to ws 9 by the user), agent
# (class match, new stableId); everything else gone. Browser not running.
{
  mkwin 0x1 chrome-x.com__-Profile_1 "Home / X" 9 15035 s1 '[12,38]' '[1256,750]' false false 0
  mkwin 0x77 org.omarchy.agent "other title" 7 19285 zz '[12,38]' '[1256,750]' false false 0
  mkwin 0x78 kitty stray 8 32000 zy '[12,38]' '[1256,750]' false false 0
} | jq -s . >"$T/fake/clients.json"
rm -f "$T/fake/dispatch.log" "$T/fake/browser-running"
"$L" restore main >"$T/restore.out" 2>&1 || true
D="$T/fake/dispatch.log"
grep -q 'hl.dsp.exec_cmd(\[\[chromium --profile-directory=.Profile 1.\]\])' "$D" || tfail "browser bootstrap for Profile 1 missing"
grep -q 'exec_cmd(\[\[chromium --profile-directory=Default\]\])' "$D" || tfail "browser bootstrap for Default missing"
grep -q 'window.move({ window = "address:0x1", workspace = "1", follow = false })' "$D" || tfail "claimed X window moved back to ws 1"
grep -q 'window.move({ window = "address:0x77", workspace = "3", follow = false })' "$D" || tfail "agent claimed by class and moved"
grep -q 'exec_cmd(\[\[uwsm-app -- xdg-terminal-exec --app-id=Alacritty' "$D" || tfail "tmux terminal launched"
grep -q 'exec_cmd(\[\[uwsm-app -- cd /home/u && /usr/bin/aether\]\], { workspace = "2 silent" })' "$D" || tfail "native launched with cwd: $(grep aether "$D" || true)"
grep -q 'exec_cmd(\[\[uwsm-app -- xdg-terminal-exec --app-id=foot --dir=/home/u/Work/tries -e bash -c .nvim notes.md; exec bash.\]\], { workspace = "3 silent", float = true, size = {800, 500}, move = {100, 100} })' "$D" || tfail "float exec rules"
grep -q 'address:0x78' "$D" && tfail "extra window touched in keep mode"
grep -q 'hl.dsp.focus({ workspace = "3" })' "$D" || tfail "focus restored"
grep -q "missing" "$T/restore.out" || tfail "summary should report unlaunchable/unmatched windows (fake never opens them)"
pass "reconcile dispatches"

echo "== switch: saves old, parks extras under special:ls-<old>, activates new"
cp "$T/clients.full.json" "$T/fake/clients.json"
"$L" save work --no-activate >/dev/null
{ mkwin 0x50 Aether Aether 2 44721 s11 '[12,38]' '[621,750]' false false 0
  mkwin 0x51 kitty extra 5 32000 q1 '[12,38]' '[621,750]' false false 0; } | jq -s . >"$T/fake/clients.json"
rm -f "$D"; touch "$T/fake/browser-running"
"$L" switch work >"$T/switch.out" 2>&1 || { cat "$T/switch.out"; tfail "switch exited non-zero"; }
[[ $(cat "$T/state/active") == work ]] || tfail "active not switched"
[[ $(jq '.windows|length' "$T/config/layouts/main.json") == 2 ]] || tfail "old layout not re-saved from live state"
grep -q 'window.move({ window = "address:0x51", workspace = "special:ls-main", follow = false })' "$D" || tfail "extra not parked"
grep -q 'window.move({ window = "address:0x50", workspace = "2", follow = false })' "$D" || tfail "aether claimed by stableId"
grep -qE 'exec_cmd\(\[\[chromium --profile-directory=[^]]*\]\]\)$' "$D" && tfail "browser bootstrap while browser running"
pass "switch/park"

echo "== watch daemon: debounce save, teardown burst skipped, SIGTERM never saves"
cp "$T/clients.full.json" "$T/fake/clients.json"
"$L" config autosave_seconds 1 >/dev/null; "$L" config periodic_seconds 600 >/dev/null
SOCK="$T/ev.sock"; export LAYOUT_SWAPPER_SOCKET="$SOCK"
python3 - "$SOCK" "$T/ev.cmd" <<'PY' &
import os, socket, sys, time
path, cmdfile = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(path); s.listen(1)
c, _ = s.accept()
sent = set()
deadline = time.time() + 40
while time.time() < deadline:
    try:
        lines = open(cmdfile).read().splitlines()
    except OSError:
        lines = []
    for ln in lines:
        if ln not in sent:
            sent.add(ln)
            if ln == "quit":
                c.close(); sys.exit(0)
            c.sendall((ln + "\n").encode())
    time.sleep(0.1)
PY
sleep 0.5
"$L" save main >/dev/null   # also makes main the active layout again
rm -f "$T/config/layouts/main.json"
"$L" watch &
WPID=$!
sleep 1
[[ $("$L" status --json | jq .watch_pid) == "$WPID" ]] || tfail "pidfile"
echo "openwindow>>abc,3,foot,title, with comma" >"$T/ev.cmd"
sleep 2.5
[[ -f $T/config/layouts/main.json ]] || tfail "event did not trigger a save"
grep -q 'saved main' "$T/state/watch.log" || tfail "watch log"
rm -f "$T/config/layouts/main.json"
printf 'closewindow>>1\ncloseWindow-2\nclosewindow>>2\nclosewindow>>3\nopenwindow>>x,1,foot,t\n' >"$T/ev.cmd"
sleep 3
[[ ! -f $T/config/layouts/main.json ]] || tfail "saved during teardown burst"
pass "burst suppressed"
# Restore lock pauses saves
touch "$T/state/restore.lock"; echo "openwindow>>y,1,foot,t2" >>"$T/ev.cmd"; sleep 2.5
[[ ! -f $T/config/layouts/main.json ]] || tfail "saved while restore lock held"
rm -f "$T/state/restore.lock"
echo "openwindow>>z,1,foot,t3" >>"$T/ev.cmd"
kill -TERM "$WPID"; wait "$WPID" 2>/dev/null || true
[[ ! -f $T/config/layouts/main.json ]] || tfail "SIGTERM path saved"
[[ ! -f $T/state/watch.pid ]] || tfail "pidfile not cleaned"
echo quit >>"$T/ev.cmd"
pass "watch daemon"

echo "== boot: ask mode uses the picker, auto restores active"
cp "$T/clients.full.json" "$T/fake/clients.json"; "$L" save main >/dev/null
"$L" config boot ask >/dev/null
echo '{"select":"work\t12 windows"}' >"$T/fake/menu.json"
rm -f "$D"; "$L" boot --no-wait >/dev/null 2>&1 || true
[[ $(cat "$T/state/active") == work ]] || tfail "boot ask did not activate the choice"
echo '{"select":"Skip\tstart with an empty desktop"}' >"$T/fake/menu.json"
"$L" boot --no-wait >/dev/null 2>&1 || true
[[ $(cat "$T/state/active") == work ]] || tfail "skip changed active"
"$L" config boot auto >/dev/null; rm -f "$D"; "$L" boot --no-wait >/dev/null 2>&1 || true
grep -q 'hl.dsp' "$D" || tfail "boot auto did not reconcile"
kill "$(cat "$T/state/watch.pid" 2>/dev/null)" 2>/dev/null || true
pass "boot modes"

echo "== menu pickers"
echo '{"input":"Focus Mode"}' >"$T/fake/menu.json"
"$L" menu save >/dev/null; [[ -f "$T/config/layouts/Focus Mode.json" && $(cat "$T/state/active") == "Focus Mode" ]] || tfail "menu save"
echo '{"input":"bad/name"}' >"$T/fake/menu.json"
if "$L" menu save >/dev/null 2>&1; then tfail "invalid name accepted"; fi
echo '{"select":"main\t12 windows"}' >"$T/fake/menu.json"
"$L" menu delete >/dev/null; [[ ! -f $T/config/layouts/main.json ]] || tfail "menu delete"
pass "menu save/delete"

echo "== update notifications: opt-in gate, changelog, dedup"
export LAYOUT_SWAPPER_NO_SYSTEMD=1
GA=(-c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false)
UP="$T/upstream"
git "${GA[@]}" init -q -b main "$UP"
( cd "$UP" && echo v1 >README.md && git "${GA[@]}" add -A && git "${GA[@]}" commit -q -m "initial release" )
PLUG="$T/plugin"
git "${GA[@]}" clone -q "$UP" "$PLUG" 2>/dev/null
export LAYOUT_SWAPPER_PLUGIN_DIR="$PLUG"
( cd "$UP" && echo x >>README.md && git "${GA[@]}" commit -qam "fix: stop parking the wrong window on switch" \
  && echo y >>README.md && git "${GA[@]}" commit -qam "feat: restore tmux terminals by re-attaching" )

[[ $("$L" update-check --print) == "" ]] || tfail "update-check ran while opted out"
[[ $("$L" update-notify status) == off ]] || tfail "default update_check not off"

"$L" update-notify on >/dev/null
[[ $("$L" update-notify status) == on ]] || tfail "opt-in did not set on"
out=$("$L" update-check --print)
grep -q "update available (2 changes)" <<<"$out" || tfail "count/title: $out"
grep -q "feat: restore tmux terminals" <<<"$out" || tfail "feature subject missing"
grep -q "fix: stop parking the wrong window" <<<"$out" || tfail "fix subject missing"
grep -q "omarchy plugin update" <<<"$out" || tfail "update command missing"

[[ $("$L" update-check --print) == "" ]] || tfail "re-notified the same version"
grep -q "update available" <<<"$("$L" update-check --print --force)" || tfail "--force did not re-report"

"$L" update-notify off >/dev/null
[[ $("$L" update-notify status) == off ]] || tfail "opt-out did not set off"
[[ $("$L" update-check --print) == "" ]] || tfail "check ran after opt-out"
unset LAYOUT_SWAPPER_PLUGIN_DIR LAYOUT_SWAPPER_NO_SYSTEMD
pass "update notifications"

echo "All tests passed."
