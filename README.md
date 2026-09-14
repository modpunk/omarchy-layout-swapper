# Layout Swapper for Omarchy

Save, switch, and auto-restore Hyprland window layouts.

Hyprland has no session restore. Layout Swapper fills that gap on Omarchy with
two distinct things:

- a **live session** that an autosave daemon keeps current as you work, so
  after a power loss, a power cycle, or a reboot every app comes back on the
  workspace it was on; and
- any number of **named snapshots** — frozen, point-in-time layouts you save on
  purpose and switch between from the bar chip, the Omarchy menu, or
  `SUPER + ALT + L`.

A named snapshot never changes on its own. Only an explicit save updates it, so
a snapshot you named after today's setup still holds *today's* setup next month.
The live session is the moving one; it is what boot restores. Switching to a
snapshot preserves what you were doing: windows the snapshot does not mention
are *parked* on a hidden workspace rather than closed, and switching back
returns them exactly where they were.

What comes back: the app, its workspace, monitor, floating geometry, pinned
and fullscreen state. Web apps come back in the right Chromium profile,
terminals in their working directory (with the program that was running in
them), agent/Claude Code terminals (`org.omarchy.agent`) on their workspace
with their command (a **fresh** agent — the window position is restored, not the
conversation), tmux/herdr terminals re-attached. Regular browser windows come
back with their tabs when Chromium's own *Continue where you left off* is on
(`install.sh` offers to turn it on).

What does not: window *contents* (unsaved text, scrollback). Only hibernate
can do that. And windows you open *on top of* a snapshot survive switching away
and back, but **not a reboot** — only the live session and explicit snapshots
survive a power cycle. If you rearranged a snapshot and want the changes to
stick, use **Save now** (below) to fold them in.

## Install

```bash
omarchy plugin add https://github.com/modpunk/omarchy-layout-swapper
~/.config/omarchy/plugins/fans.omarchy.layout-swapper/install.sh
omarchy bar put fans.omarchy.layout-swapper
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

## Everyday use

The autosave daemon keeps your **live session** current as you open, move, and
close windows, so you never have to save it by hand — it is what comes back
after a reboot. **Named snapshots** are separate and frozen: they change only
when you save them. The bar chip's tooltip names the last snapshot you applied.

Three ways in:

| where | what it does |
|---|---|
| bar chip `󰕰` | **click** switch snapshot · **right-click** freeze the current windows as a new snapshot · **middle-click** set login behaviour |
| `SUPER + ALT + L` | open the switcher |
| Omarchy menu → **Layouts** | switch, save as, save now, restore, login mode, delete, show |

**Switching snapshots.** Pick one from the switcher. The tool first checkpoints
your live session, then *parks* the windows the chosen snapshot does not mention
on a hidden workspace (they are not closed) and brings the snapshot up. Switch
back and your parked windows return exactly where they were, contents intact. So
switching never loses anything you had open.

**Creating a snapshot.** The switcher's last row, **New layout…**, and
right-clicking the bar chip both freeze your current windows under a new name.
The snapshot is a fixed capture from that moment; it will not drift as you keep
working. Rearrange freely — nothing is written back to it unless you ask.

**Updating a snapshot.** Rearranged things and want the snapshot to match? Use
**Save now** (Omarchy menu → Layouts, or `omarchy-layout-swapper save <name>`).
It overwrites that snapshot in place and keeps a backup. This is the only thing
that changes a named snapshot — nothing else does.

**At login.** By default your last session comes back automatically a few
seconds after you log in. Middle-click the bar chip (or the menu's *login
mode*) to be asked instead — the picker offers **Last session** plus every named
snapshot.

**Recovering.** The session and every snapshot keep their last five autosave
backups, so if one ends up wrong you can roll back:

```
omarchy-layout-swapper restore --from-backup            # most recent backup of the last snapshot
omarchy-layout-swapper restore <name> --from-backup 2   # the 2nd most recent of <name>
```

### Command line

```
omarchy-layout-swapper save <name>              freeze/update the named snapshot <name>
omarchy-layout-swapper save                     checkpoint the live session (no name)
omarchy-layout-swapper switch <name>            checkpoint the session, park extras, bring up <name>
omarchy-layout-swapper restore [name] [--close] reconcile onto the current desktop (keep or close extras)
omarchy-layout-swapper restore --from-backup    from the most recent autosave backup (or N-th)
omarchy-layout-swapper list | show | delete | rename
omarchy-layout-swapper config boot auto|ask     restore the session at login, or show the picker
omarchy-layout-swapper status
```

Named snapshots are plain JSON under `~/.config/omarchy-layout-swapper/layouts/`.
The live session (`session.json`), the park manifests (`parked/`), and autosave
backups (last 5 each) live under `~/.local/state/omarchy-layout-swapper/`.

## Updating

Layout Swapper is a git-managed Omarchy plugin, so you pull new versions with
Omarchy's own command:

```bash
omarchy plugin update fans.omarchy.layout-swapper   # just this plugin
omarchy plugin update                               # every git-managed plugin
```

That fetches the latest commit, shows you the diff, fast-forwards your copy,
re-validates the manifest, and reloads the shell. Omarchy's "update available"
bar indicator tracks the system, not plugins, so it will not tell you a new
version of this plugin exists. After updating, restart the shell once
(`omarchy restart shell`) if the bar chip does not refresh on its own.

### Update alerts

The bar chip tells you when a newer version is published, so you do not have to
run `omarchy plugin update` on a hunch. When one is out, a small dot appears on
the `󰕰` icon; the next click opens a popup listing what changed (from this
plugin's `CHANGELOG.md`) with an **Update…** button that opens a terminal and
runs `omarchy plugin update` for you (it shows the diff and asks first).
**Later** hides that version until the next one.

The check is one small request to the plugin's repository on load and every six
hours, cached in `~/.cache/omarchy-layout-swapper/`; offline it uses the last
answer. It sends no personal data — only a User-Agent naming the plugin. It is
**on by default**; turn it off with:

```bash
omarchy-layout-swapper config update_check false     # `true` to turn back on
```

(or set `"update_check": false` in the widget's `shell.json` entry). See
[docs/update-alerts.md](docs/update-alerts.md) for the full design. So keep the
`CHANGELOG.md` bullets descriptive — they are what your users read in the popup.

## How it works

- **Save** reads `hyprctl clients -j` and derives a launch command per
  window: Omarchy web apps from their desktop files and `{ webapp = … }`
  bindings (class `chrome-<host>__-<Profile>` → `omarchy-launch-webapp <url>
  --profile-directory=…`), PWAs from the class (`--app-id`), terminals and
  agent/Claude Code terminals from the child shell's cwd and foreground job
  (`/proc`), native apps from their command line and cwd. Transient shell
  windows and windows on special workspaces (scratchpad, parked) are skipped.
  A named `save` freezes a snapshot under `layouts/`; a bare `save` (and the
  autosave daemon) writes the live `session.json` — the two never touch each
  other's files.
- **Restore** is a reconcile: existing windows are claimed (by Hyprland's
  stable id, then class + title, then class) and moved into place; missing
  ones are launched one at a time with `hl.dsp.exec_cmd` and matched as they
  appear; everything is then placed by address (`hl.dsp.window.move / float /
  resize / pin / fullscreen_state`). If no browser is running, it is started
  once per saved profile first so Chromium's own session restore can bring
  the tabs back. Legacy string dispatchers are used as a fallback on older
  Hyprland.
- **Switch** checkpoints the live session (it never rewrites the frozen snapshot
  you are leaving), parks every window the target snapshot does not mention on
  `special:ls-<old>` — recording each one's origin workspace and geometry in a
  `parked/<old>.json` manifest — and brings the target up. Switching back
  reclaims recorded members by id and un-parks everything the manifest lists, so
  even windows the snapshot never mentioned come back where they were.
- **Watch** listens on Hyprland's event socket, saves the **live session** 5 s
  after the last window event (and every 60 s), pauses while a restore runs,
  ignores a burst of window closes (that is a logout, not a layout), and
  never saves on SIGTERM. A non-empty session is never overwritten by an empty
  snapshot. Named snapshots are frozen — the daemon never writes them.

## Development

`tests/run.sh` drives the CLI against a fake compositor (JSON fixtures and a
dispatch log), a fake `/proc` tree, and a fake event socket; no Hyprland
needed. CI runs it together with shellcheck and a manifest check.

MIT © modpunk (omarchy.fans)
