import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Bar widget + popup for Cloud Drives: one row per provider (Google Drive,
// OneDrive, iCloud Drive, Proton Drive) with connect / mount / open / disconnect actions.
// All the work happens in bin/omarchy-cloud-drives; interactive steps
// (sign-in, 2FA, confirmations) run in a floating terminal.
Panel {
  id: root
  moduleName: "edbron.cloud-drives"
  ipcTarget: "edbron.cloud-drives"
  manageIpc: false

  readonly property string script: String(Qt.resolvedUrl("bin/omarchy-cloud-drives")).replace(/^file:\/\//, "")

  property bool rcloneInstalled: false
  property bool encrypted: false
  property bool keyring: false
  property string mountRoot: ""
  property var providers: []
  property bool busy: false

  readonly property int mountedCount: {
    var n = 0
    for (var i = 0; i < providers.length; i++) if (providers[i].mounted) n++
    return n
  }
  readonly property int connectedCount: {
    var n = 0
    for (var i = 0; i < providers.length; i++) if (providers[i].configured) n++
    return n
  }
  readonly property bool secure: rcloneInstalled && encrypted && keyring
  readonly property color dim: Qt.darker(bar.foreground, 1.4)

  // Cursor: one row per provider; h/l moves across that row's action pills.
  property bool cursorActive: false
  property int selectedIndex: 0
  property var actionCursor: ({})

  function actionsFor(p) {
    if (!p) return []
    if (!p.configured) return ["connect"]
    var a = [p.mounted ? "unmount" : "mount"]
    if (p.mounted) a.unshift("open")
    a.push("disconnect")
    return a
  }
  readonly property var actionLabels: ({ connect: "Connect", open: "Open", mount: "Mount", unmount: "Unmount", disconnect: "Forget" })
  readonly property var actionIcons: ({ connect: "󰌘", open: "󰉋", mount: "󰐕", unmount: "󰅖", disconnect: "󰩹" })

  function actionCursorFor(row) { return actionCursor[row] !== undefined ? actionCursor[row] : 0 }
  function setActionCursor(row, idx) {
    var next = Object.assign({}, actionCursor); next[row] = idx; actionCursor = next
  }

  function moveCursor(delta) {
    var n = providers.length
    if (!n) return
    selectedIndex = Math.max(0, Math.min(n - 1, selectedIndex + delta))
  }
  function moveCursorH(delta) {
    var acts = actionsFor(providers[selectedIndex])
    if (!acts.length) return
    setActionCursor(selectedIndex, Math.max(0, Math.min(acts.length - 1, actionCursorFor(selectedIndex) + delta)))
  }
  function activateCursor() {
    var p = providers[selectedIndex]
    if (!p) return
    var acts = actionsFor(p)
    run(acts[Math.min(actionCursorFor(selectedIndex), acts.length - 1)], p.id)
  }

  function refresh() { if (!stateProc.running) stateProc.running = true }

  // connect / disconnect need a terminal (browser sign-in, 2FA, confirm);
  // mount / unmount / open are silent.
  function run(action, id) {
    if (busy) return
    if (action === "connect" || action === "disconnect") {
      Quickshell.execDetached([script, "launch", action, id])
      close()
      return
    }
    busy = true
    actionProc.command = [script, action, id]
    actionProc.running = true
  }

  function stateIpc() {
    return JSON.stringify({ rclone: rcloneInstalled, encrypted: encrypted, keyring: keyring, providers: providers })
  }

  IpcHandler {
    target: "edbron.cloud-drives"
    function state(): string { return root.stateIpc() }
    function refresh(): string { root.refresh(); return "ok" }
    function mount(id: string): string { root.run("mount", id); return "ok" }
    function unmount(id: string): string { root.run("unmount", id); return "ok" }
    function connect(id: string): string { root.run("connect", id); return "ok" }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) { refresh(); cursorActive = false; selectedIndex = 0 }
  onProvidersChanged: if (selectedIndex >= providers.length) selectedIndex = 0

  // Mounts can appear/vanish from the terminal flow, so poll: fast while
  // open, slow otherwise.
  Timer {
    interval: root.opened ? 2000 : 30000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: [root.script, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(String(text || "{}"))
          root.rcloneInstalled = !!s.rclone
          root.encrypted = !!s.encrypted
          root.keyring = !!s.keyring
          root.mountRoot = s.root || ""
          root.providers = s.providers || []
        } catch (e) {
          root.providers = []
        }
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) { root.busy = false; root.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.mountedCount > 0 ? "󰅟" : "󰅧"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: "󰅟"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Cloud Drives"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              width: parent.width
              elide: Text.ElideRight
            }

            Text {
              text: {
                if (!root.rcloneInstalled) return "NOT SET UP · CONNECT A DRIVE TO BEGIN"
                if (!root.connectedCount) return "NO ACCOUNTS CONNECTED"
                return root.mountedCount + " OF " + root.connectedCount + " MOUNTED · " + (root.secure ? "KEYRING-ENCRYPTED" : "CONFIG NOT ENCRYPTED")
              }
              color: root.secure || !root.connectedCount ? root.dim : root.bar.urgent
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              width: parent.width
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Providers ----------
        Column {
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: provHeader.implicitHeight
            PanelSectionHeader {
              id: provHeader
              text: "DRIVES"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: root.mountRoot.replace(/^\/home\/[^\/]+/, "~")
              color: root.dim
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Repeater {
            model: root.providers
            ProviderRow {
              required property var modelData
              required property int index
              width: panelColumn.width
              provider: modelData
              rowIndex: index
            }
          }
        }

        // ---------- Footnote ----------
        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Sign-in happens in your browser (Google, Microsoft) or via account + 2FA (iCloud, Proton). Tokens are stored in an rclone config encrypted with a key that only lives in your login keyring."
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component ActionPill: Button {
    id: pill
    required property string action
    required property int actionIndex
    required property int rowIndex
    required property string providerId

    text: root.actionLabels[action]
    iconText: root.actionIcons[action]
    fontSize: Style.font.caption
    foreground: action === "disconnect" ? root.bar.urgent : root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    enabled: !root.busy
    hasCursor: root.cursorActive && root.selectedIndex === rowIndex && root.actionCursorFor(rowIndex) === actionIndex

    onClicked: root.run(action, providerId)
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.selectedIndex = pill.rowIndex
      root.setActionCursor(pill.rowIndex, pill.actionIndex)
    }
  }

  component ProviderRow: CursorSurface {
    id: row
    required property var provider
    required property int rowIndex
    readonly property var actions: root.actionsFor(provider)

    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    current: provider.mounted
    foreground: root.bar.foreground
    fill: Style.hoverFillFor(root.bar.foreground, Color.accent)
    currentFill: Style.selectedFillFor(root.bar.foreground, Color.accent)
    implicitHeight: inner.implicitHeight + Style.spacing.xl

    Column {
      id: inner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(6)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: row.provider.glyph
          color: row.provider.configured ? root.bar.foreground : root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(22) - Style.space(8) - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: row.provider.name
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            text: {
              if (!row.provider.configured) return "Not connected"
              if (row.provider.mounted) return "Mounted · " + row.provider.path.replace(/^\/home\/[^\/]+/, "~")
              if (row.provider.active) return "Mounting…"
              return "Connected · not mounted"
            }
            color: root.dim
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Text {
          text: row.provider.mounted ? "󰄬" : ""
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.subtitle
          width: Style.space(16)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Row {
        spacing: Style.spacing.xs
        anchors.right: parent.right
        Repeater {
          model: row.actions
          ActionPill {
            required property string modelData
            required property int index
            action: modelData
            actionIndex: index
            rowIndex: row.rowIndex
            providerId: row.provider.id
          }
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      z: -1
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.selectedIndex = row.rowIndex }
    }
  }
}
