# Layout Swapper for Omarchy

Save, switch, and auto-restore Hyprland window layouts.

Hyprland has no session restore. Layout Swapper fills that gap on Omarchy:
an autosave daemon keeps the **active layout** current, so after a power loss,
a power cycle, or a reboot every app comes back on the workspace it was on.
You can keep several **named layouts** and swap between them from the bar
chip, the Omarchy menu, or `SUPER + ALT + L`. Switching preserves the layout
you leave: its windows are *parked* on a hidden workspace rather than closed,
so switching back is instant and nothing you had open is lost.

What comes back: the app, its workspace, monitor, floating geometry, pinned
and fullscreen state. Web apps come back in the right Chromium profile,
terminals in their working directory (with the program that was running in
them), agent terminals (`org.omarchy.agent`) with their command and
directory, tmux/herdr terminals re-attached. Regular browser windows come back
with their tabs when Chromium's own *Continue where you left off* is on
(`install.sh` offers to turn it on).

What does not: window *contents* (unsaved text, scrollback). Only hibernate
can do that.

## Install

```bash
omarchy plugin add https://github.com/modpunk/omarchy-layout-swapper
~/.config/omarchy/plugins/fans.omarchy.layout-swapper/install.sh
omarchy bar add fans.omarchy.layout-swapper
```

`install.sh` asks before each step and backs up any file it appends to:

1. symlink the CLI into `~/.local/bin`
2. keybinding `SUPER + ALT + L` → layout switcher (`~/.config/hypr/bindings.lua`)
3. a **Layouts** submenu in the Omarchy menu
4. optional: snapshot right before Shutdown / Reboot / Logout from the System menu
5. a post-boot hook that starts the daemon and restores the last layout after login
6. Chromium *Continue where you left off* in every profile (only while Chromium is closed)
7. the first snapshot, and the daemon, right now

`uninstall.sh` reverses 1–5 (`--purge` also deletes saved layouts).

## Use

| where | what |
|---|---|
| bar chip `󰕰 main` | click: switch · right-click: save current as new layout · middle-click: login mode |
| `SUPER + ALT + L` | switch layout (the picker's last row saves the current windows as a new layout) |
| Omarchy menu → Layouts | switch, save as, save now, restore, login mode, delete, show |

```
omarchy-layout-swapper save [name]              snapshot now (default: active layout)
omarchy-layout-swapper switch <name>            save current, park its windows, bring up <name>
omarchy-layout-swapper restore [name] [--close] reconcile onto the current desktop (keep or close extras)
omarchy-layout-swapper restore --from-backup    from the most recent autosave backup (or N-th)
omarchy-layout-swapper list | show | delete | rename
omarchy-layout-swapper config boot auto|ask     restore automatically at login, or show the picker
omarchy-layout-swapper status
```

Layouts are plain JSON under `~/.config/omarchy-layout-swapper/layouts/`;
autosave backups (last 5 per layout) under
`~/.local/state/omarchy-layout-swapper/backups/`.

## How it works

- **Save** reads `hyprctl clients -j` and derives a launch command per
  window: Omarchy web apps from their desktop files and `{ webapp = … }`
  bindings (class `chrome-<host>__-<Profile>` → `omarchy-launch-webapp <url>
  --profile-directory=…`), PWAs from the class (`--app-id`), terminals from the
  child shell's cwd and foreground job (`/proc`), native apps from their
  command line and cwd. Transient shell windows and parked windows are skipped.
- **Restore** is a reconcile: existing windows are claimed (by Hyprland's
  stable id, then class + title, then class) and moved into place; missing
  ones are launched one at a time with `hl.dsp.exec_cmd` and matched as they
  appear; everything is then placed by address (`hl.dsp.window.move / float /
  resize / pin / fullscreen_state`). If no browser is running, it is started
  once per saved profile first so Chromium's own session restore can bring
  the tabs back. Legacy string dispatchers are used as a fallback on older
  Hyprland.
- **Switch** saves the active layout, parks every window the target layout
  does not mention on `special:ls-<old>`, and brings the target up. Switching
  back reclaims the parked windows by id.
- **Watch** listens on Hyprland's event socket, saves the active layout 5 s
  after the last window event (and every 60 s), pauses while a restore runs,
  ignores a burst of window closes (that is a logout, not a layout), and
  never saves on SIGTERM. A non-empty layout is never overwritten by an empty
  snapshot.

## Development

`tests/run.sh` drives the CLI against a fake compositor (JSON fixtures and a
dispatch log), a fake `/proc` tree, and a fake event socket; no Hyprland
needed. CI runs it together with shellcheck and a manifest check.

MIT © modpunk (omarchy.fans)
