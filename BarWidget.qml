import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar chip for the Layout Swapper: a single icon whose tooltip names the
// last-applied layout. Everything that touches windows lives in
// bin/omarchy-layout-swapper; this widget only reads one small state file
// (the last-applied layout name, for the tooltip) and shells out fixed command
// strings through bar.run (`bash -lc <command>`), so nothing parsed from
// disk reaches the shell process as code.
//
// BarIconButton is a fixed one-slot-wide icon, so the visible mark and the
// clickable area must be a single glyph — the layout name goes in the
// tooltip, not the label (a multi-word label overflows the slot and leaves
// most of the chip unclickable).
//
//   left click    switch layout (picker; "New layout…" freezes a new snapshot)
//   right click   freeze the current windows as a new snapshot
//   middle click  choose what happens at login (restore automatically / ask)
BarWidget {
  id: root
  moduleName: "fans.omarchy.layout-swapper"

  // Let the bar summon the switcher by plugin id (open/close/opened is the
  // Bar.findPanelWidget contract). There is no in-shell panel, so opened
  // stays false and open() just runs the picker.
  property bool opened: false
  function open() { root.run("menu switch") }
  function close() { opened = false }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string activeFile: stateHome + "/omarchy-layout-swapper/active"
  readonly property string pluginBin: home + "/.config/omarchy/plugins/fans.omarchy.layout-swapper/bin/omarchy-layout-swapper"

  // The CLI is on PATH once install.sh has symlinked it; fall back to the
  // copy inside this plugin folder so the widget works right after
  // `omarchy plugin add`.
  readonly property string cli: "$(if command -v omarchy-layout-swapper >/dev/null 2>&1; then echo omarchy-layout-swapper; else echo '" + pluginBin + "'; fi)"

  function run(args) {
    if (root.bar && typeof root.bar.run === "function")
      root.bar.run(cli + " " + args)
  }

  readonly property string activeName: {
    var t = String(activeState.text()).trim()
    return t !== "" ? t : "main"
  }

  FileView {
    id: activeState
    path: root.activeFile
    watchChanges: true
    onFileChanged: reload()
    onLoadFailed: function(error) { /* no state yet: show the default */ }
  }

  // The state file is replaced atomically (write + rename), which can drop a
  // filesystem watch; a slow poll keeps the tooltip honest.
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: activeState.reload()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰕰"                            // nf-md-view_dashboard
    slotSize: Style.bar.iconSlot
    tooltipText: "Last layout · " + root.activeName + "\nclick: switch · right: save new · middle: login mode"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.run("menu save")
      else if (b === Qt.MiddleButton) root.run("menu boot-mode")
      else root.run("menu switch")
    }
  }
}
