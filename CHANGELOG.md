# Changelog

The bar chip reads the newest sections of this file to tell you what changed
when an update is available. Keep one short line per bullet.

## 0.2.0 — Frozen snapshots, agent terminals, in-app update alert (2026-09-14)

- Named layouts are now frozen snapshots that change only when you save them; a separate live session is autosaved and is what boot restores. Fixes a bug where a saved layout got overwritten with your current desktop.
- Claude Code and agent terminals are now saved and restored by workspace and position (a relaunch is a fresh agent; opt out via config ignore_classes).
- The bar chip now alerts you when a newer version is published, showing what changed; on by default, one small check every six hours, config update_check false to turn it off.
- Switching no longer rewrites the layout you leave, and windows you opened on top of a snapshot are parked and returned when you switch back.
- Menu: Save now re-saves the last-applied snapshot in place; Save current as… freezes a new one; the login picker offers Last session.

## 0.1.0 — Initial release (2026-09-08)

- Save, switch, and auto-restore Hyprland window layouts on Omarchy.
- Autosave daemon over Hyprland IPC events, debounced, with rolling backups.
- Web apps restored in the right Chromium profile, terminals in their working directory, tmux/herdr re-attached, browser tabs via Chromium session restore.
- Bar chip, SUPER + ALT + L, and an Omarchy Layouts menu; login auto-restore with an ask-at-login toggle.
