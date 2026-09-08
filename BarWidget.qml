import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar chip for the Layout Swapper: shows the active layout name and opens
// the layout pickers. Everything that touches windows lives in
// bin/omarchy-layout-swapper; this widget only reads one small state file
// (the active layout name) and shells out fixed command strings through
// bar.run (`bash -lc <command>`), so nothing parsed from disk reaches the
// shell process as code.
//
//   left click    switch layout (picker; "New layout…" saves the current one)
//   right click   save the current windows as a new layout
//   middle click  choose what happens at login (restore automatically / ask)
BarWidget {
  id: root
  moduleName: "fans.omarchy.layout-swapper"

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
  // filesystem watch; a slow poll keeps the label honest.
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
    text: "󰕰 " + root.activeName        // nf-md-view_dashboard + layout name
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Layout · " + root.activeName + "  (click: switch, right: save new, middle: login mode)"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.run("menu save")
      else if (b === Qt.MiddleButton) root.run("menu boot-mode")
      else root.run("menu switch")
    }
  }
}
