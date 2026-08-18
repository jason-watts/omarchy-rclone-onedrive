import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "jason.rclone-onedrive"
  ipcTarget: "jason.rclone-onedrive"
  manageIpc: false

  property string focusSection: "header"
  property int fileIndex: 0
  property bool cursorActive: false
  property int phraseIndex: 0
  property double nowMs: Date.now()

  readonly property var activePhrases: [
    "Mirroring OneDrive",
    "Caching clouds",
    "Keeping OneDrive close",
    "Watching the mount",
    "Filing from afar",
    "Holding the fuse",
    "Syncing the quiet way"
  ]
  readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: store.alarming ? urgent : (store.active ? foreground : dim)
  readonly property color barIconColor: store.alarming ? urgent : (store.active ? barForeground : Qt.darker(barForeground, 1.55))
  readonly property string toggleHint: store.active ? "Stop mount" : "Start mount"
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property var displayFiles: store.transferring.length > 0 ? store.transferring : store.files
  readonly property bool showingTransfers: store.transferring.length > 0
  readonly property bool showSetup: store.needsSetup || store.needsAuth || store.needsMount || !store.rcloneInstalled
  readonly property var setupAccounts: [
    { id: "personal", label: "Personal Microsoft account", caption: "login.microsoftonline.com/consumers" },
    { id: "business", label: "Work or school", caption: "login.microsoftonline.com/organizations" },
    { id: "sharepoint", label: "SharePoint library", caption: "Same work login, then pick a library" }
  ]
  property int setupIndex: 0

  function ensureCursor() {
    if (root.showSetup) {
      if (focusSection !== "setup" && focusSection !== "setupGo" && focusSection !== "header")
        focusSection = "setup"
      if (setupIndex < 0) setupIndex = 0
      if (setupIndex >= setupAccounts.length) setupIndex = setupAccounts.length - 1
      return
    }
    if (displayFiles.length === 0) {
      focusSection = "header"
      fileIndex = 0
      return
    }
    if (focusSection !== "files" && focusSection !== "header" && focusSection !== "openFiles" && focusSection !== "openTerm")
      focusSection = "files"
    if (fileIndex >= displayFiles.length) fileIndex = Math.max(0, displayFiles.length - 1)
    if (fileIndex < 0) fileIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) focusSection = root.showSetup ? "setup" : "openFiles"
      return
    }
    if (focusSection === "setup") {
      if (dy < 0 && setupIndex === 0) {
        setHeaderCursor()
        return
      }
      if (dy < 0) {
        setupIndex -= 1
        return
      }
      if (dy > 0 && setupIndex < setupAccounts.length - 1) {
        setupIndex += 1
        return
      }
      if (dy > 0) focusSection = "setupGo"
      return
    }
    if (focusSection === "setupGo") {
      if (dy < 0) focusSection = "setup"
      return
    }
    if (focusSection === "openFiles") {
      if (dy < 0) {
        setHeaderCursor()
        return
      }
      if (dy > 0) focusSection = "openTerm"
      return
    }
    if (focusSection === "openTerm") {
      if (dy < 0) {
        focusSection = "openFiles"
        return
      }
      if (dy > 0 && displayFiles.length > 0) {
        focusSection = "files"
        fileIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        focusSection = "openTerm"
        return
      }
      fileIndex = Math.max(0, Math.min(displayFiles.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function toggleRunning() {
    if (!store.busy) store.toggleRunning()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      if (root.showSetup) focusSection = "setup"
      else toggleRunning()
    } else if (focusSection === "setup") {
      store.setupAccount = setupAccounts[setupIndex].id
    } else if (focusSection === "setupGo") {
      root.runSetupAction()
    } else if (focusSection === "openFiles") store.openInFiles()
    else if (focusSection === "openTerm") openTerminal()
    else if (focusSection === "files") store.openFile(selectedFile())
  }

  function selectedFile() {
    if (displayFiles.length === 0) return null
    return displayFiles[Math.max(0, Math.min(fileIndex, displayFiles.length - 1))]
  }

  function setFileCursor(index) {
    cursorActive = true
    focusSection = "files"
    fileIndex = index
    scrollCursorIntoView()
  }

  function setOpenFilesCursor() {
    cursorActive = true
    focusSection = "openFiles"
  }

  function setOpenTermCursor() {
    cursorActive = true
    focusSection = "openTerm"
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length)
      scrollItemIntoView(fileColumn.children[fileIndex])
  }

  function refreshNow() {
    nowMs = Date.now()
    store.refresh()
    store.refreshAbout()
  }

  function runSetupAction() {
    if (store.busy) return
    if (!store.rcloneInstalled) store.runSetup("install-rclone")
    else if (store.needsAuth && !store.needsSetup) store.runSetup("reconnect")
    else if (store.needsMount && !store.needsSetup) store.runSetup("setup")
    else store.runSetup("setup")
  }

  function setSetupCursor(index) {
    cursorActive = true
    focusSection = "setup"
    setupIndex = index
    store.setupAccount = setupAccounts[index].id
  }

  function openTerminal() {
    // Drop exclusive layer-shell keyboard before spawning a terminal.
    root.close()
    Qt.callLater(function() { store.openInTerminal() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    refreshNow()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }
  onFileIndexChanged: scrollCursorIntoView()

  Service {
    id: store
    settings: root.settings
  }

  Connections {
    target: store
    function onFilesChanged() { root.ensureCursor() }
    function onTransferringChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function status(): string { return store.statusText }
    function files(): string { store.openInFiles(); return "ok" }
    function terminal(): string { root.openTerminal(); return "ok" }
    function setup(): string { root.runSetupAction(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: store.alarming
    tooltipText: Model.tooltip({
      remote: store.remote,
      state: store.state,
      statusText: store.statusText,
      transferring: store.transferring
    })
    iconComponent: Component {
      Item {
        OneDriveIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
          opacity: store.active ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else if (buttonCode === Qt.MiddleButton) store.openInFiles()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "o" || t === "O") store.openInFiles()
        else if (t === "t" || t === "T") root.openTerminal()
        else if (t === "p" || t === "P") root.toggleRunning()
        else if (t === "l" || t === "L") root.runSetupAction()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.headerHasCursor
            function focusHero() { root.setHeaderCursor() }

            PanelHero {
              id: hero
              width: parent.width
              title: "OneDrive"
              meta: store.needsSetup ? "Set up rclone" : (store.healthy ? root.heroPhraseText : store.statusText)
              detail: store.remote || (store.needsSetup ? "First-time setup" : "")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: store.active ? 1.0 : 0.5
              iconComponent: Component {
                OneDriveIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: !store.needsSetup
                  checked: store.active
                  busy: store.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: root.toggleRunning()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Column {
            visible: root.showSetup
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: !store.rcloneInstalled ? "INSTALL" : (store.needsAuth && !store.needsSetup ? "SIGN IN AGAIN" : "MICROSOFT ACCOUNT")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: store.rcloneInstalled ? root.setupAccounts : []
              SetupChoice {
                required property var modelData
                required property int index
                width: parent.width
                account: modelData
                rowIndex: index
              }
            }

            SetupGo {
              width: parent.width
            }
          }

          Text {
            visible: store.actionStatus !== "" || store.lastError !== ""
            width: parent.width
            text: store.actionStatus !== "" ? store.actionStatus : store.lastError
            color: store.lastError !== "" && store.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: !store.needsSetup
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoPair { label: "State"; value: store.statusText }
            InfoPair { label: "Up"; value: store.running ? Model.uptimeText(store.startedMs, root.nowMs) : "—" }
            InfoPair { label: "Restarts"; value: String(store.restarts) }
            InfoPair { label: "Stored"; value: store.aboutRefreshing && !store.quotaKnown ? "Checking…" : Model.usageText(store.usedBytes, store.quotaBytes, store.quotaKnown) }
            InfoPair {
              visible: store.rcAvailable && store.speed > 0
              label: "Speed"
              value: Model.formatSpeed(store.speed)
            }
            InfoPair {
              label: "Cache"
              value: store.cacheFiles + " · " + Model.formatBytes(store.cacheBytes)
            }
            InfoPair { label: "Mount"; value: store.mountPath }
          }

          Text {
            visible: !store.needsSetup && store.excludeNote !== ""
            width: parent.width
            text: store.excludeNote
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: store.lastJournal !== "" && store.alarming
            width: parent.width
            text: store.lastJournal
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: !store.needsSetup && store.mountPath !== ""
            width: parent.width
            spacing: Style.space(6)

            OpenTargetRow {
              width: parent.width
              section: "openFiles"
              iconText: "󰉋"
              label: "Open in Files"
              caption: store.mountPath
              onActivate: store.openInFiles()
              onHover: root.setOpenFilesCursor()
            }

            OpenTargetRow {
              width: parent.width
              section: "openTerm"
              iconText: "󰆍"
              label: "Open in Terminal"
              caption: store.mountPath
              onActivate: root.openTerminal()
              onHover: root.setOpenTermCursor()
            }
          }

          PanelSeparator {
            visible: !store.needsSetup
            foreground: root.foreground
          }

          Column {
            visible: !store.needsSetup
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.showingTransfers ? "IN FLIGHT" : "RECENT CACHE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.displayFiles.length === 0
              width: parent.width
              text: store.rcAvailable
                ? "No cached or in-flight files."
                : "No cached files. Enable rclone RC for live transfers."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Column {
              id: fileColumn
              visible: root.displayFiles.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.displayFiles
                FileRow {
                  required property var modelData
                  required property int index
                  width: fileColumn.width
                  file: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: phraseTimer
    interval: 2800
    running: root.opened && store.healthy
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  component SetupChoice: CursorSurface {
    id: choiceRow
    property var account: ({})
    property int rowIndex: 0
    readonly property bool selected: store.setupAccount === String(account.id || "")

    hasCursor: root.cursorActive && root.focusSection === "setup" && root.setupIndex === rowIndex
    foreground: root.foreground
    implicitHeight: choiceBody.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setSetupCursor(choiceRow.rowIndex)
      onClicked: root.setSetupCursor(choiceRow.rowIndex)
    }

    RowLayout {
      id: choiceBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: choiceRow.selected ? "●" : "○"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: String(choiceRow.account.label || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: String(choiceRow.account.caption || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component SetupGo: CursorSurface {
    id: goRow
    hasCursor: root.cursorActive && root.focusSection === "setupGo"
    foreground: root.foreground
    implicitHeight: goBody.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: store.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
      enabled: !store.busy
      onEntered: {
        root.cursorActive = true
        root.focusSection = "setupGo"
      }
      onClicked: root.runSetupAction()
    }

    RowLayout {
      id: goBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: "󰌋"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: !store.rcloneInstalled
            ? "Install rclone"
            : (store.needsAuth && !store.needsSetup ? "Sign in again" : "Sign in with Microsoft")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: store.busy
            ? "Waiting for the browser…"
            : "Opens the correct Microsoft login, then starts the mount"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component OpenTargetRow: CursorSurface {
    id: openRow
    property string section: ""
    property string iconText: ""
    property string label: ""
    property string caption: ""
    signal activate()
    signal hover()

    hasCursor: root.cursorActive && root.focusSection === section
    foreground: root.foreground
    implicitHeight: openContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: openRow.hover()
      onClicked: openRow.activate()
    }

    RowLayout {
      id: openContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: openRow.iconText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)
        Text {
          Layout.fillWidth: true
          text: openRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: openRow.caption
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component FileRow: CursorSurface {
    id: fileRow
    property var file: null
    property int rowIndex: 0
    readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"

    hasCursor: root.cursorActive && root.focusSection === "files" && root.fileIndex === rowIndex
    foreground: root.foreground
    implicitHeight: fileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setFileCursor(fileRow.rowIndex)
      onClicked: store.openFile(fileRow.file)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: Model.fileGlyph(fileRow.fileName)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: fileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: fileRow.fileName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.showingTransfers ? Model.transferMeta(fileRow.file) : Model.fileMeta(fileRow.file, root.nowMs)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)
    visible: value !== ""

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
