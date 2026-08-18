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
  property int headerIndex: 0
  readonly property bool canOpenMount: store.mountPath !== ""
  readonly property bool canToggleMount: !store.needsSetup
  readonly property int filesHeaderIndex: canOpenMount ? 0 : -1
  readonly property int termHeaderIndex: canOpenMount ? 1 : -1
  readonly property int toggleHeaderIndex: canToggleMount ? (canOpenMount ? 2 : 0) : -1
  readonly property int headerActionCount: (canOpenMount ? 2 : 0) + (canToggleMount ? 1 : 0)
  readonly property bool filesHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === filesHeaderIndex
  readonly property bool termHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === termHeaderIndex
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex
  readonly property var displayFiles: store.transferring.length > 0 ? store.transferring : store.files
  readonly property bool showingTransfers: store.transferring.length > 0
  readonly property bool showSetup: store.needsSetup || store.needsAuth || store.needsMount || !store.rcloneInstalled
  readonly property var setupAccounts: [
    { id: "personal", label: "Personal Microsoft account", caption: "login.microsoftonline.com/consumers" },
    { id: "business", label: "Work or school", caption: "login.microsoftonline.com/organizations" },
    { id: "sharepoint", label: "SharePoint library", caption: "Same work login, then pick a library" }
  ]
  property int setupIndex: 0
  readonly property real desiredPanelBody: header.implicitHeight + Style.space(12)
    + Math.min(middle.implicitHeight, Style.space(340))
    + (footer.visible ? Style.space(12) + footer.implicitHeight : 0)

  onHeaderActionCountChanged: clampHeaderIndex()

  function ensureCursor() {
    if (root.showSetup) {
      if (focusSection !== "setup" && focusSection !== "setupGo" && focusSection !== "header")
        focusSection = "setup"
      if (setupIndex < 0) setupIndex = 0
      if (setupIndex >= setupAccounts.length) setupIndex = setupAccounts.length - 1
      return
    }
    if (displayFiles.length === 0) {
      if (focusSection !== "header" && focusSection !== "linger" && focusSection !== "remove")
        focusSection = "header"
      fileIndex = 0
      return
    }
    if (focusSection !== "files" && focusSection !== "header" && focusSection !== "linger" && focusSection !== "remove")
      focusSection = "files"
    if (fileIndex >= displayFiles.length) fileIndex = Math.max(0, displayFiles.length - 1)
    if (fileIndex < 0) fileIndex = 0
  }

  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max) headerIndex = max
    if (headerIndex < 0) headerIndex = 0
  }

  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dx !== 0 && focusSection === "header") {
      selectHeaderByDelta(dx)
      return
    }
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0) {
        if (root.showSetup) focusSection = "setup"
        else if (displayFiles.length > 0) {
          focusSection = "files"
          fileIndex = 0
          scrollCursorIntoView()
        } else {
          focusSection = "linger"
          scrollCursorIntoView()
        }
      }
      return
    }
    if (focusSection === "linger") {
      if (dy < 0) {
        if (displayFiles.length > 0) {
          focusSection = "files"
          fileIndex = displayFiles.length - 1
          scrollCursorIntoView()
        } else {
          setHeaderCursor()
        }
        return
      }
      if (dy > 0) {
        focusSection = "remove"
        scrollCursorIntoView()
      }
      return
    }
    if (focusSection === "remove") {
      if (dy < 0) {
        focusSection = "linger"
        scrollCursorIntoView()
      }
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
    if (focusSection === "files") {
      if (dy < 0 && fileIndex === 0) {
        setHeaderCursor()
        return
      }
      if (dy > 0 && fileIndex === displayFiles.length - 1) {
        focusSection = "linger"
        scrollCursorIntoView()
        return
      }
      fileIndex = Math.max(0, Math.min(displayFiles.length - 1, fileIndex + dy))
      scrollCursorIntoView()
    }
  }

  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    if (index !== undefined && index >= 0) headerIndex = index
    clampHeaderIndex()
    if (panelFlick) panelFlick.contentY = 0
  }

  function toggleRunning() {
    if (!store.busy) store.toggleRunning()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") {
      if (headerIndex === filesHeaderIndex) store.openInFiles()
      else if (headerIndex === termHeaderIndex) openTerminal()
      else if (headerIndex === toggleHeaderIndex) toggleRunning()
      else if (root.showSetup) focusSection = "setup"
    } else if (focusSection === "setup") {
      store.setupAccount = setupAccounts[setupIndex].id
    } else if (focusSection === "setupGo") {
      root.runSetupAction()
    } else if (focusSection === "linger") {
      store.toggleLinger()
    } else if (focusSection === "remove") {
      root.askRemoveRemote()
    } else if (focusSection === "files") store.openFile(selectedFile())
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
    if (focusSection === "linger") {
      scrollItemIntoView(lingerRow)
      return
    }
    if (focusSection === "remove") {
      scrollItemIntoView(removeRow)
      return
    }
    if (focusSection === "files" && fileColumn && fileIndex >= 0 && fileIndex < fileColumn.children.length)
      scrollItemIntoView(fileColumn.children[fileIndex])
  }

  function refreshNow() {
    nowMs = Date.now()
    store.refresh()
    store.refreshAbout()
  }

  function runSetupAction() {
    if (!store.rcloneInstalled) {
      store.runSetup("install-rclone")
      return
    }
    if (store.needsAuth && !store.needsSetup) {
      store.runSetup("reconnect")
      return
    }
    store.runSetup("setup")
  }

  function askRemoveRemote() {
    if (store.mutating || String(store.remote || "") === "") return
    removeConfirm.selectedIndex = 1
    removeConfirm.opened = true
    Qt.callLater(function() { if (removeConfirm) removeConfirm.forceActiveFocus() })
  }

  function cancelRemoveRemote() {
    removeConfirm.opened = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function confirmRemoveRemote() {
    removeConfirm.opened = false
    if (keyCatcher) keyCatcher.forceActiveFocus()
    store.removeRemote()
  }

  function setSetupCursor(index) {
    cursorActive = true
    focusSection = "setup"
    setupIndex = index
  }

  function selectSetupAccount(index) {
    var next = setupAccounts[index].id
    setSetupCursor(index)
    if (store.setupAccount === next) return
    store.setupAccount = next
    store.cancelSetup()
    store.actionStatus = ""
    store.lastError = ""
  }

  function openTerminal() {
    // Drop exclusive layer-shell keyboard before spawning a terminal.
    root.close()
    Qt.callLater(function() { store.openInTerminal() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened) {
      removeConfirm.opened = false
      return
    }
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
    function onNeedsSetupChanged() {
      if (store.needsSetup) {
        root.focusSection = "setup"
        if (panelFlick) panelFlick.contentY = 0
      }
    }
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
    function remove(): string { root.askRemoveRemote(); return "confirm" }
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
    contentHeight: panel.fittedContentHeight(root.desiredPanelBody, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: removeConfirm.opened
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
        else if (t === "b" || t === "B") store.toggleLinger()
        else if (t === "l" || t === "L") root.runSetupAction()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        Item {
          id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

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
                Row {
                  spacing: Style.space(8)

                  Button {
                    visible: root.canOpenMount
                    iconText: "󰉋"
                    tooltipText: "Open in Files"
                    foreground: hero.foreground
                    fontFamily: hero.fontFamily
                    iconSize: Style.font.subtitle * 1.5
                    horizontalPadding: Style.space(5)
                    verticalPadding: Style.space(2)
                    hasCursor: root.filesHeaderHasCursor
                    anchors.verticalCenter: parent.verticalCenter
                    onHovered: function(on) { if (on) root.setHeaderCursor(root.filesHeaderIndex) }
                    onClicked: store.openInFiles()
                  }

                  Button {
                    visible: root.canOpenMount
                    iconText: "󰆍"
                    tooltipText: "Open in Terminal"
                    foreground: hero.foreground
                    fontFamily: hero.fontFamily
                    iconSize: Style.font.subtitle * 1.5
                    horizontalPadding: Style.space(5)
                    verticalPadding: Style.space(2)
                    hasCursor: root.termHeaderHasCursor
                    anchors.verticalCenter: parent.verticalCenter
                    onHovered: function(on) { if (on) root.setHeaderCursor(root.termHeaderIndex) }
                    onClicked: root.openTerminal()
                  }

                  ToggleSwitch {
                    id: powerSwitch
                    visible: root.canToggleMount
                    checked: store.active
                    busy: store.busy
                    hasCursor: root.toggleHeaderHasCursor
                    foreground: hero.foreground
                    anchors.verticalCenter: parent.verticalCenter
                    onHovered: function(on) { if (on) root.setHeaderCursor(root.toggleHeaderIndex) }
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
          }

        Flickable {
          id: panelFlick
          width: parent.width
          height: Math.max(0, parent.height - header.height - (footer.visible ? footer.height : 0) - parent.spacing * (footer.visible ? 2 : 1))
          contentWidth: width
          contentHeight: middle.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: middle
            width: panelFlick.width
            spacing: Style.space(12)

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

        Column {
          id: footer
          width: parent.width
          visible: !store.needsSetup
          spacing: Style.space(2)

          PanelSeparator {
            visible: !store.needsSetup
            foreground: root.foreground
          }

          CursorSurface {
            id: lingerRow
            visible: !store.needsSetup
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "linger"
            foreground: root.foreground
            implicitHeight: lingerBody.implicitHeight + Style.space(6)

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.cursorActive = true
                root.focusSection = "linger"
              }
              onClicked: store.toggleLinger()
            }

            RowLayout {
              id: lingerBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)
                Text {
                  Layout.fillWidth: true
                  text: "Mount at boot"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                Text {
                  Layout.fillWidth: true
                  text: store.lingerActive ? "Starts before login" : "Starts when you log in"
                  color: root.dim
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              ToggleSwitch {
                checked: store.lingerActive === true
                interactive: false
                cursorRing: false
                trackHeight: 16
                foreground: root.foreground
                Layout.alignment: Qt.AlignVCenter
              }
            }
          }

          CursorSurface {
            id: removeRow
            visible: !store.needsSetup && store.remote !== ""
            width: parent.width
            hasCursor: root.cursorActive && root.focusSection === "remove"
            foreground: root.urgent
            implicitHeight: removeBody.implicitHeight + Style.space(6)

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: {
                root.cursorActive = true
                root.focusSection = "remove"
              }
              onClicked: root.askRemoveRemote()
            }

            RowLayout {
              id: removeBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(8)

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)
                Text {
                  Layout.fillWidth: true
                  text: "Remove remote"
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
                Text {
                  Layout.fillWidth: true
                  text: "Deletes " + store.remote + " from rclone"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        z: 20
        opened: false
        message: store.remote !== ""
          ? "Remove rclone remote “" + store.remote + "”? The mount stops and the local login is deleted. Files stay in OneDrive."
          : "Remove this rclone remote?"
        cancelText: "Cancel"
        confirmText: "Remove"
        background: Color.popups.background
        foreground: root.foreground
        fontFamily: root.fontFamily
        focus: opened
        Keys.onPressed: function(event) {
          if (removeConfirm.handleKey(event)) event.accepted = true
        }
        onCanceled: root.cancelRemoveRemote()
        onConfirmed: root.confirmRemoveRemote()
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

    hasCursor: root.cursorActive && root.focusSection === "setup" && root.setupIndex === rowIndex && !selected
    current: selected
    foreground: root.foreground
    implicitHeight: choiceBody.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.selectSetupAccount(choiceRow.rowIndex)
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
      cursorShape: Qt.PointingHandCursor
      enabled: true
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
            : (store.needsAuth && !store.needsSetup
              ? "Sign in again"
              : "Sign in with Microsoft")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          text: store.setupRunning
            ? "Waiting for the browser…"
            : "Signs in, names the remote from the account domain, and mounts it"
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
