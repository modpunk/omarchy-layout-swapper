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
//
// Updates (docs/update-alerts.md): lib/update.sh checks the published version on
// load and every six hours (cached, one small request). When a newer one is out
// a dot appears on the chip and the next left click opens a small popup with what
// changed and an Update… button; Later hides that version and the click goes back
// to switching layouts.
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
  // This file's folder as a plain path (Qt.resolvedUrl gives a file:// URL), so
  // the update check runs this plugin's own copy wherever it is installed.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string updateHelper: pluginDir + "/lib/update.sh"
  readonly property var childEnv: ({ "PATH": "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin" })

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

  // ---- updates (docs/update-alerts.md) ---------------------------------------
  // lib/update.sh checks the published version on load and every six hours
  // (cached, one small request). When a newer one is out, a dot appears on the
  // chip and the next click opens a popup with what changed; Later hides that
  // version and the click goes back to switching layouts.
  property string version: ""
  property var updateInfo: null
  readonly property bool updateAvailable: !!updateInfo && updateInfo.update_available === true
                                          && updateInfo.dismissed !== updateInfo.latest
  readonly property bool updateMismatch: !!updateInfo && updateInfo.mismatch === true
  readonly property string updateKey: updateAvailable ? String(updateInfo.latest) : (updateMismatch ? "mismatch" : "")
  property string updateHiddenKey: ""
  readonly property bool updatePending: updateKey !== "" && updateKey !== updateHiddenKey

  FileView {
    path: root.pluginDir + "/manifest.json"
    printErrors: false
    onLoaded: {
      try { root.version = String(JSON.parse(text()).version || "") } catch (e) { root.version = "" }
      root.checkUpdates()
    }
  }
  function checkUpdates() {
    if (root.setting("update_check", true) === false || updateProc.running) return
    updateProc.command = ["/usr/bin/bash", root.updateHelper, "check", root.version]
    updateProc.running = true
  }
  Process {
    id: updateProc
    environment: root.childEnv
    stdout: StdioCollector { id: updateOut; waitForEnd: true }
    onExited: function(code) { try { root.updateInfo = JSON.parse(String(updateOut.text || "")) } catch (e) { root.updateInfo = null } }
  }
  Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; onTriggered: root.checkUpdates() }
  function runUpdate() {
    root.updateHiddenKey = root.updateKey
    updatePopup.open = false
    Quickshell.execDetached({
      command: ["/usr/bin/bash", root.updateHelper, "run", root.updateAvailable ? "all" : "install"],
      environment: root.childEnv,
      workingDirectory: root.home
    })
  }
  function dismissUpdate() {
    root.updateHiddenKey = root.updateKey
    updatePopup.open = false
    if (root.updateAvailable && root.updateInfo.latest)
      Quickshell.execDetached({
        command: ["/usr/bin/bash", root.updateHelper, "dismiss", String(root.updateInfo.latest)],
        environment: root.childEnv,
        workingDirectory: root.home
      })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰕰"                            // nf-md-view_dashboard
    slotSize: Style.bar.iconSlot
    tooltipText: "Last layout · " + root.activeName + "\nclick: switch · right: save new · middle: login mode"
      + (root.updateAvailable ? "\n· " + root.updateInfo.latest + " is available"
         : (root.updateMismatch ? "\n· finish updating" : ""))

    onPressed: function(b) {
      if (b === Qt.RightButton) root.run("menu save")
      else if (b === Qt.MiddleButton) root.run("menu boot-mode")
      else if (root.updatePending) updatePopup.open = !updatePopup.open
      else root.run("menu switch")
    }

    Rectangle {
      visible: root.updatePending
      anchors.top: parent.top; anchors.right: parent.right
      anchors.margins: Style.space(3)
      width: Style.space(6); height: width; radius: width / 2
      color: Color.accent
    }
  }

  // ---- update popup (docs/update-alerts.md) -----------------------------------
  PopupCard {
    id: updatePopup
    anchorItem: button
    bar: root.bar
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(updateCol.implicitHeight)
    Column {
      id: updateCol
      width: parent.width
      spacing: Style.space(4)
      Text {
        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: root.updateAvailable
              ? "Layout Swapper " + root.updateInfo.latest + " is available (you have " + root.version + ")"
              : "Finish updating Layout Swapper"
        color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
      }
      Repeater {
        model: root.updateAvailable ? root.updateInfo.notes.slice(0, 4) : []
        delegate: Text {
          required property var modelData
          width: updateCol.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
          text: "•  " + modelData
          color: Color.popups.text; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
      }
      Text {
        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: root.updateAvailable
              ? "Update opens a terminal: omarchy plugin update shows the changes and asks, then install.sh asks."
              : "Run install.sh once so everything matches. It asks before changing anything."
        color: Color.popups.text; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption
      }
      Item { width: 1; height: Style.space(2) }
      Row {
        spacing: Style.space(4)
        Button { text: root.updateAvailable ? "Update…" : "Finish update…"; bordered: true; foreground: Color.accent; onClicked: root.runUpdate() }
        Button { text: "Later"; bordered: true; foreground: Color.popups.text; onClicked: root.dismissUpdate() }
        Button { text: "Switch layout"; foreground: Color.popups.text; onClicked: { updatePopup.open = false; root.run("menu switch") } }
      }
    }
  }
}
