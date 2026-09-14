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
  mkwin 0xc org.gnome.Nautilus logos 7 194829 s12 '[12,38]' '[621,750]' false false 0
  mkwin 0xd org.omarchy.menu menu 3 99 s13 '[0,0]' '[1,1]' true false 0
  mkwin 0xe foot parked special:ls-other 32000 s14 '[0,0]' '[1,1]' false false 0
  mkwin 0xf com.scratch.App scratch special:scratchpad 40000 s15 '[0,0]' '[1,1]' false false 0
} | jq -s . >"$T/fake/clients.json"

echo "== save: launch derivation"
"$L" save main >/dev/null || tfail "save exited non-zero"
J="$T/config/layouts/main.json"
[[ -f $J ]] || tfail "layout file missing"
n=$(jq '.windows|length' "$J"); [[ $n == 12 ]] || tfail "expected 12 windows (menu, parked, scratchpad excluded; agent now captured), got $n"
kind() { jq -r --arg c "$1" '.windows[]|select(.class==$c)|.launch.kind' "$J" | head -1; }
cmd() { jq -r --arg c "$1" '.windows[]|select(.class==$c)|.launch.cmd' "$J" | head -1; }
[[ $(kind chrome-x.com__-Profile_1) == webapp ]] || tfail "webapp kind"
[[ $(cmd chrome-x.com__-Profile_1) == "omarchy-launch-webapp https://x.com/ --profile-directory='Profile 1'" ]] || tfail "webapp cmd: $(cmd chrome-x.com__-Profile_1)"
[[ $(cmd chrome-grok.com__-Default) == "omarchy-launch-webapp https://grok.com --profile-directory=Default" ]] || tfail "webapp from bindings: $(cmd chrome-grok.com__-Default)"
[[ $(cmd chrome-discord.com__channels__me-Default) == "omarchy-launch-webapp https://discord.com/channels/@me --profile-directory=Default" ]] || tfail "webapp with path: $(cmd chrome-discord.com__channels__me-Default)"
[[ $(kind chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2) == pwa ]] || tfail "pwa kind"
[[ $(cmd chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2) == "chromium --profile-directory='Profile 2' --app-id=pacgdjiidkfdhilcljkeebfoklekebig" ]] || tfail "pwa cmd: $(cmd chrome-pacgdjiidkfdhilcljkeebfoklekebig-Profile_2)"
[[ $(kind chromium) == chromium && $(cmd chromium) == "chromium --new-window" ]] || tfail "chromium: $(cmd chromium)"
[[ $(cmd foot) == "xdg-terminal-exec --app-id=foot --dir=/home/u/Work/tries -e bash -c 'nvim notes.md; exec bash'" ]] || tfail "foreground job: $(cmd foot)"
[[ $(kind Alacritty) == tmux && $(cmd Alacritty) == "xdg-terminal-exec --app-id=Alacritty --dir=/home/u -e bash -c 'tmux attach || tmux new -s Work'" ]] || tfail "tmux: $(cmd Alacritty)"
idle=$(jq -r '.windows[]|select(.class=="foot" and .title=="zsh")|.launch.cmd' "$J")
[[ $idle == "xdg-terminal-exec --app-id=foot --dir=/home/u/Work" ]] || tfail "idle shell: $idle"
[[ $(kind Aether) == native && $(cmd Aether) == "/usr/bin/aether" ]] || tfail "native: $(cmd Aether)"
[[ $(jq -r '.windows[]|select(.class=="Aether")|.launch.cwd' "$J") == /home/u ]] || tfail "native cwd"
[[ $(cmd org.gnome.Nautilus) == "/usr/bin/nautilus --new-window" ]] || tfail "nautilus"
# Agent terminals are now captured (position/command only). The top-bar pop-up is
# a layer surface, never a client, so there is nothing to filter for it.
[[ $(jq '[.windows[]|select(.class=="org.omarchy.agent")]|length' "$J") == 1 ]] || tfail "agent terminal should be captured in layouts"
[[ $(kind org.omarchy.agent) == agent ]] || tfail "agent kind"
[[ $(cmd org.omarchy.agent) == "xdg-terminal-exec --app-id=org.omarchy.agent --dir=/home/u/Work -e /home/u/.local/share/mise/installs/claude/latest/claude --permission-mode auto" ]] || tfail "agent cmd: $(cmd org.omarchy.agent)"
[[ $(jq '[.windows[]|select(.workspace|startswith("special:"))]|length' "$J") == 0 ]] || tfail "special-workspace windows (scratchpad) should be excluded"
[[ $(jq -r '.windows[]|select(.title=="nvim notes.md")|[.floating,.pinned,.size[0]]|@csv' "$J") == "true,true,800" ]] || tfail "float/pin/size"
[[ $(jq -r '.windows[]|select(.title=="zsh")|.fullscreen' "$J") == 2 ]] || tfail "fullscreen int"
[[ $(jq -r '.active_workspace' "$J") == 3 && $(jq -r '.monitors[0]' "$J") == eDP-1 ]] || tfail "meta"
[[ $(cat "$T/state/active") == main ]] || tfail "active set"
pass "12 records; agent captured, special-workspace windows excluded"

echo "== agent windows can still be opted out via ignore_classes"
(
  export LAYOUT_SWAPPER_CONFIG_DIR="$T/cfg-noagent" LAYOUT_SWAPPER_STATE_DIR="$T/st-noagent"
  "$L" config ignore_classes org.omarchy.menu,org.omarchy.agent >/dev/null
  "$L" save na >/dev/null
  JN="$T/cfg-noagent/layouts/na.json"
  [[ $(jq '[.windows[]|select(.class=="org.omarchy.agent")]|length' "$JN") == 0 ]] || tfail "agent not excluded when added to ignore_classes"
)
pass "agent opt-out via config works"

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
# Live desktop: X webapp (same stableId, moved to ws 9 by the user); an agent
# terminal (now claimed by class and placed on its saved workspace); a stray
# kitty (extra, left alone in keep mode). Browser not running.
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
grep -q 'window.move({ window = "address:0x77", workspace = "3", follow = false })' "$D" || tfail "agent terminal claimed and placed on its saved workspace"
grep -q 'exec_cmd(\[\[uwsm-app -- xdg-terminal-exec --app-id=Alacritty' "$D" || tfail "tmux terminal launched"
grep -q 'exec_cmd(\[\[uwsm-app -- cd /home/u && /usr/bin/aether\]\], { workspace = "2 silent" })' "$D" || tfail "native launched with cwd: $(grep aether "$D" || true)"
grep -q 'exec_cmd(\[\[uwsm-app -- xdg-terminal-exec --app-id=foot --dir=/home/u/Work/tries -e bash -c .nvim notes.md; exec bash.\]\], { workspace = "3 silent", float = true, size = {800, 500}, move = {100, 100} })' "$D" || tfail "float exec rules"
grep -q 'address:0x78' "$D" && tfail "extra window touched in keep mode"
grep -q 'hl.dsp.focus({ workspace = "3" })' "$D" || tfail "focus restored"
grep -q "missing" "$T/restore.out" || tfail "summary should report unlaunchable/unmatched windows (fake never opens them)"
pass "reconcile dispatches"

echo "== switch: frozen old layout untouched, session checkpointed, extras parked"
cp "$T/clients.full.json" "$T/fake/clients.json"
"$L" save work --no-activate >/dev/null
mainbefore=$(jq '.windows|length' "$T/config/layouts/main.json")
rm -f "$T/state/session.json"
{ mkwin 0x50 Aether Aether 2 44721 s11 '[12,38]' '[621,750]' false false 0
  mkwin 0x51 kitty extra 5 32000 q1 '[12,38]' '[621,750]' false false 0; } | jq -s . >"$T/fake/clients.json"
rm -f "$D"; touch "$T/fake/browser-running"
"$L" switch work >"$T/switch.out" 2>&1 || { cat "$T/switch.out"; tfail "switch exited non-zero"; }
[[ $(cat "$T/state/active") == work ]] || tfail "active not switched"
# Frozen snapshots: the layout we left must NOT be rewritten (this was the data-loss bug).
[[ $(jq '.windows|length' "$T/config/layouts/main.json") == "$mainbefore" ]] || tfail "old named layout was clobbered on switch-away"
# Instead the live desktop is checkpointed into the session file (2 live windows).
[[ $(jq '.windows|length' "$T/state/session.json") == 2 ]] || tfail "session not checkpointed on switch"
grep -q 'window.move({ window = "address:0x51", workspace = "special:ls-main", follow = false })' "$D" || tfail "extra not parked"
grep -q 'window.move({ window = "address:0x50", workspace = "2", follow = false })' "$D" || tfail "aether claimed by stableId"
grep -qE 'exec_cmd\(\[\[chromium --profile-directory=[^]]*\]\]\)$' "$D" && tfail "browser bootstrap while browser running"
# A park manifest recorded the parked extra and where it came from.
[[ $(jq -r '."0x51".workspace' "$T/state/parked/main.json") == 5 ]] || tfail "park manifest missing the parked window's origin workspace"
pass "switch: old frozen, session checkpointed, park manifest written"

echo "== unpark: switching to a layout returns windows it parked earlier, even unlisted ones"
# The extra 0x51 was parked under 'main' above; 'main' does not list it. Switching
# back to main must un-park it to its recorded workspace 5, not strand it.
{ mkwin 0x50 Aether Aether 2 44721 s11 '[12,38]' '[621,750]' false false 0
  mkwin 0x51 kitty extra "special:ls-main" 32000 q1 '[12,38]' '[621,750]' false false 0; } | jq -s . >"$T/fake/clients.json"
rm -f "$D"
"$L" switch main >"$T/unpark.out" 2>&1 || { cat "$T/unpark.out"; tfail "switch main exited non-zero"; }
grep -q 'window.move({ window = "address:0x51", workspace = "5", follow = false })' "$D" || tfail "parked window not un-parked to its origin workspace"
[[ ! -f "$T/state/parked/main.json" ]] || tfail "park manifest not consumed after un-park"
pass "unpark restores unlisted parked windows"

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
"$L" save main >/dev/null   # a named snapshot the daemon must NOT touch
rm -f "$T/state/session.json"
mainlen=$(jq '.windows|length' "$T/config/layouts/main.json")
"$L" watch &
WPID=$!
sleep 1
[[ $("$L" status --json | jq .watch_pid) == "$WPID" ]] || tfail "pidfile"
echo "openwindow>>abc,3,foot,title, with comma" >"$T/ev.cmd"
sleep 2.5
[[ -f $T/state/session.json ]] || tfail "event did not trigger a session save"
grep -q 'saved session' "$T/state/watch.log" || tfail "watch log"
# The daemon must write the live session, never the named snapshot.
[[ $(jq '.windows|length' "$T/config/layouts/main.json") == "$mainlen" ]] || tfail "daemon overwrote the named layout"
rm -f "$T/state/session.json"
printf 'closewindow>>1\ncloseWindow-2\nclosewindow>>2\nclosewindow>>3\nopenwindow>>x,1,foot,t\n' >"$T/ev.cmd"
sleep 3
[[ ! -f $T/state/session.json ]] || tfail "saved during teardown burst"
pass "burst suppressed"
# Restore lock pauses saves
touch "$T/state/restore.lock"; echo "openwindow>>y,1,foot,t2" >>"$T/ev.cmd"; sleep 2.5
[[ ! -f $T/state/session.json ]] || tfail "saved while restore lock held"
rm -f "$T/state/restore.lock"
echo "openwindow>>z,1,foot,t3" >>"$T/ev.cmd"
kill -TERM "$WPID"; wait "$WPID" 2>/dev/null || true
[[ ! -f $T/state/session.json ]] || tfail "SIGTERM path saved"
[[ ! -f $T/state/watch.pid ]] || tfail "pidfile not cleaned"
echo quit >>"$T/ev.cmd"
pass "watch daemon"

echo "== boot: auto restores the live session, falls back to named, ask uses the picker"
cp "$T/clients.full.json" "$T/fake/clients.json"
"$L" save main >/dev/null
"$L" save work --no-activate >/dev/null

# auto + a session present -> restores the session
"$L" save >/dev/null   # bare save = session checkpoint
"$L" config boot auto >/dev/null
rm -f "$D"; "$L" boot --no-wait >/dev/null 2>&1 || true
grep -q 'hl.dsp' "$D" || tfail "boot auto did not restore the session"
kill "$(cat "$T/state/watch.pid" 2>/dev/null)" 2>/dev/null || true

# auto + no session yet (fresh upgrade) -> falls back to the last-applied named layout
rm -f "$T/state/session.json"; echo work >"$T/state/active"
rm -f "$D"; "$L" boot --no-wait >/dev/null 2>&1 || true
grep -q 'hl.dsp' "$D" || tfail "boot auto did not fall back to the named layout"
kill "$(cat "$T/state/watch.pid" 2>/dev/null)" 2>/dev/null || true

# ask mode -> the picker choice is applied
"$L" config boot ask >/dev/null
echo main >"$T/state/active"
echo '{"select":"work\t12 windows"}' >"$T/fake/menu.json"
rm -f "$D"; "$L" boot --no-wait >/dev/null 2>&1 || true
[[ $(cat "$T/state/active") == work ]] || tfail "boot ask did not activate the choice"
kill "$(cat "$T/state/watch.pid" 2>/dev/null)" 2>/dev/null || true

# ask mode -> Skip leaves things alone
echo work >"$T/state/active"
echo '{"select":"Skip\tstart with an empty desktop"}' >"$T/fake/menu.json"
"$L" boot --no-wait >/dev/null 2>&1 || true
[[ $(cat "$T/state/active") == work ]] || tfail "skip changed active"
kill "$(cat "$T/state/watch.pid" 2>/dev/null)" 2>/dev/null || true
"$L" config boot auto >/dev/null
pass "boot modes (session, fallback, ask, skip)"

echo "== menu pickers"
cp "$T/clients.full.json" "$T/fake/clients.json"
echo '{"input":"Focus Mode"}' >"$T/fake/menu.json"
"$L" menu save >/dev/null; [[ -f "$T/config/layouts/Focus Mode.json" && $(cat "$T/state/active") == "Focus Mode" ]] || tfail "menu save"
echo '{"input":"bad/name"}' >"$T/fake/menu.json"
if "$L" menu save >/dev/null 2>&1; then tfail "invalid name accepted"; fi
# save-now re-saves the last-applied snapshot in place, picking up new changes.
jq '.[0].title="changed by save-now"' "$T/clients.full.json" >"$T/fake/clients.json"
"$L" menu save-now >/dev/null
[[ $(jq -r '[.windows[]|select(.title=="changed by save-now")]|length' "$T/config/layouts/Focus Mode.json") == 1 ]] || tfail "save-now did not update the last-applied snapshot"
cp "$T/clients.full.json" "$T/fake/clients.json"
echo '{"select":"main\t12 windows"}' >"$T/fake/menu.json"
"$L" menu delete >/dev/null; [[ ! -f $T/config/layouts/main.json ]] || tfail "menu delete"
pass "menu save/save-now/delete"

echo "== delete and rename carry the park manifest (no stranded windows)"
cp "$T/clients.full.json" "$T/fake/clients.json"
"$L" save keeper --no-activate >/dev/null
echo '{"0xZ":{"stable_id":"z","workspace":"4","at":[0,0],"size":[1,1],"floating":false,"fullscreen":0,"pinned":false}}' >"$T/state/parked/keeper.json"
"$L" rename keeper keeper2 >/dev/null
[[ -f "$T/state/parked/keeper2.json" && ! -f "$T/state/parked/keeper.json" ]] || tfail "rename did not carry the park manifest"
{ mkwin 0xZ foot leftover "special:ls-keeper2" 32000 z '[0,0]' '[1,1]' false false 0; } | jq -s . >"$T/fake/clients.json"
rm -f "$D"; echo main >"$T/state/active"
"$L" delete keeper2 >/dev/null
grep -q 'window.move({ window = "address:0xZ", workspace = "4", follow = false })' "$D" || tfail "delete did not un-park parked windows before removing the layout"
[[ ! -f "$T/config/layouts/keeper2.json" && ! -f "$T/state/parked/keeper2.json" ]] || tfail "delete cleanup incomplete"
pass "delete/rename park-manifest handling"

echo "== update alert: the shared lib/update.sh check against file:// fixtures (docs/update-alerts.md)"
j() { jq -r "$1" <<<"$2"; }
R="$T/raw"; mkdir -p "$R"
export OMARCHY_PLUGIN_UPDATE_RAW="file://$R" XDG_CACHE_HOME="$T/cache" XDG_CONFIG_HOME="$T/xdgcfg"
jq '.version = "9.9.9"' "$ROOT/manifest.json" >"$R/manifest.json"
printf '# Changelog\n\n## 9.9.9\n\n- Newest thing\n\n## 9.9.8\n\n- Older thing\n\n## 0.1.0\n\n- Ancient\n' >"$R/CHANGELOG.md"
out=$("$L" update-check 0.1.0) || tfail "update-check exited $?"
[[ $(j .latest "$out") == 9.9.9 && $(j .update_available "$out") == true && $(j '.notes|join(",")' "$out") == "Newest thing,Older thing" ]] || tfail "update-check: $out"
[[ $(j .panel "$out") == 0.1.0 && $(j .cli "$out") == "$(jq -r .version "$ROOT/manifest.json")" && $(j .mismatch "$out") == true ]] || tfail "older widget is a mismatch: $out"
out=$("$L" update-check); [[ $(j .mismatch "$out") == false && $(j .update_available "$out") == true ]] || tfail "same version, no mismatch: $out"
[[ -f $T/cache/omarchy-layout-swapper/update-check.json ]] || tfail "no cache written"
out=$(OMARCHY_PLUGIN_UPDATE_RAW=file:///nonexistent "$L" update-check); [[ $(j .latest "$out") == 9.9.9 ]] || tfail "offline answer from cache: $out"
"$L" update-dismiss 9.9.9 || tfail "update-dismiss"
[[ $("$L" update-check | jq -r .dismissed) == 9.9.9 ]] || tfail "dismissed not recorded"
jq '.version = "0.0.1"' "$ROOT/manifest.json" >"$R/manifest.json"
out=$("$L" update-check --force); [[ $(j .update_available "$out") == false && $(j '.notes|length' "$out") == 0 ]] || tfail "nothing newer: $out"
mkdir -p "$XDG_CONFIG_HOME/omarchy-layout-swapper"; echo '{"update_check": false}' >"$XDG_CONFIG_HOME/omarchy-layout-swapper/config.json"
out=$("$L" update-check --force); [[ $(j .enabled "$out") == false && $(j .latest "$out") == null ]] || tfail "opt-out: $out"
rm "$XDG_CONFIG_HOME/omarchy-layout-swapper/config.json"
out=$(OMARCHY_PLUGIN_UPDATE_PRINT=1 "$L" update-run all); [[ $(j '.argv[0]' "$out") == *omarchy-launch-tui && $(j '.argv[-1]' "$out") == all ]] || tfail "update-run argv: $out"
! "$L" update-run bogus 2>/dev/null || tfail "update-run rejects unknown steps"
echo 'not json' >"$T/cache/omarchy-layout-swapper/update-check.json"
"$L" update-dismiss 1.2.3 && [[ $("$L" update-check --force | jq -r .dismissed) == 1.2.3 ]] || tfail "a broken cache file is replaced, not kept"
unset OMARCHY_PLUGIN_UPDATE_RAW XDG_CACHE_HOME XDG_CONFIG_HOME
pass "check, notes, cache, offline, dismiss, opt-out, run, broken cache"

echo "All tests passed."
