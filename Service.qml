import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})

  property string state: "stopped"
  property string statusText: "Checking…"
  property string remote: ""
  property string mountPath: ""
  property string unit: ""
  property bool running: false
  property bool mounted: false
  property bool probeOk: false
  property bool rcAvailable: false
  property int restarts: 0
  property double startedMs: 0
  property double speed: 0
  property int errors: 0
  property int cacheFiles: 0
  property double cacheBytes: 0
  property var transferring: []
  property var files: []
  property string excludeNote: "Personal Vault excluded"
  property string lastJournal: ""
  property bool authHint: false
  property bool rcloneInstalled: true
  property bool needsSetup: false
  property bool needsMount: false
  property bool needsAuth: false
  property string setupAccount: "personal"
  property string setupRemote: ""
  property bool setupPending: false
  property string setupDomain: ""
  property bool linger: false
  property string unitScope: "user"
  property bool refreshing: false
  property bool aboutRefreshing: false
  property double usedBytes: 0
  property double quotaBytes: 0
  property double freeBytes: 0
  property bool quotaKnown: false
  property string actionStatus: ""
  property string lastError: ""

  property int _desired: -1
  property int _lingerDesired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  readonly property bool lingerActive: _lingerDesired === -1 ? linger : (_lingerDesired === 1)
  readonly property bool healthy: state === "healthy"
  readonly property bool alarming: Model.alarming(state)
  readonly property bool busy: statusProcess.running || aboutProcess.running || controlProcess.running || setupProcess.running || lingerProcess.running
  readonly property bool mutating: controlProcess.running || setupProcess.running || lingerProcess.running
  readonly property bool setupRunning: setupProcess.running
  readonly property string setupHelperPath: resolvedSetupHelper()
  readonly property string helperPath: resolvedHelper()
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 15, 5, 3600)
  readonly property int aboutIntervalSec: intSetting("aboutIntervalSec", 300, 60, 3600)

  property string _statusOutput: ""
  property string _statusError: ""
  property string _aboutOutput: ""
  property string _aboutError: ""
  property string _controlOutput: ""
  property string _controlError: ""
  property string _setupOutput: ""
  property string _setupError: ""
  property string _lingerOutput: ""
  property string _lingerError: ""
  property string _prevState: ""
  property bool _suppressNotify: false
  property bool _setupCancelled: false
  property string _setupRestart: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function resolvedUrl(name) {
    var url = Qt.resolvedUrl(name).toString()
    if (url.indexOf("file://") === 0) {
      var path = url.substring(7)
      if (path.indexOf("//") === 0) path = path.substring(1)
      try { return decodeURIComponent(path) } catch (e) { return path }
    }
    return url
  }

  function resolvedHelper() {
    return resolvedUrl("status.py")
  }

  function resolvedSetupHelper() {
    return resolvedUrl("setup.py")
  }

  function helperArgs() {
    var args = []
    var remote = String(setting("remote", ""))
    var mountPath = String(setting("mountPath", ""))
    var unit = String(setting("unit", ""))
    var rcUrl = String(setting("rcUrl", "http://127.0.0.1:5572"))
    if (remote !== "") args = args.concat(["--remote", remote])
    if (mountPath !== "") args = args.concat(["--mount", mountPath])
    if (unit !== "") args = args.concat(["--unit", unit])
    if (rcUrl !== "") args = args.concat(["--rc", rcUrl])
    return args
  }

  function elide(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 160 ? value.substring(0, 157) + "…" : value
  }

  function refresh() {
    if (statusProcess.running || helperPath === "") return
    _statusOutput = ""
    _statusError = ""
    refreshing = true
    statusProcess.command = ["/usr/bin/python3", helperPath].concat(helperArgs())
    statusProcess.running = true
  }

  function refreshAbout() {
    if (aboutProcess.running || helperPath === "") return
    _aboutOutput = ""
    _aboutError = ""
    aboutRefreshing = true
    aboutProcess.command = ["/usr/bin/python3", helperPath, "about"].concat(helperArgs())
    aboutProcess.running = true
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok && !parsed.state) {
      lastError = parsed.lastError || "Failed to read OneDrive status"
      return
    }
    var nextState = String(parsed.state || "stopped")
    maybeNotify(_prevState, nextState)
    _prevState = nextState
    state = nextState
    statusText = String(parsed.statusText || nextState)
    remote = String(parsed.remote || setting("remote", ""))
    mountPath = String(parsed.mountPath || setting("mountPath", ""))
    unit = String(parsed.unit || setting("unit", ""))
    running = parsed.running === true
    mounted = parsed.mounted === true
    probeOk = parsed.probeOk === true
    rcAvailable = parsed.rcAvailable === true
    restarts = Number(parsed.restarts || 0)
    startedMs = Number(parsed.startedMs || 0)
    speed = Number(parsed.speed || 0)
    errors = Number(parsed.errors || 0)
    cacheFiles = Number(parsed.cacheFiles || 0)
    cacheBytes = Number(parsed.cacheBytes || 0)
    transferring = parsed.transferring || []
    files = parsed.files || []
    excludeNote = parsed.excludeNote !== undefined && parsed.excludeNote !== null
      ? String(parsed.excludeNote)
      : ""
    lastJournal = String(parsed.lastJournal || "")
    authHint = parsed.authHint === true
    rcloneInstalled = parsed.rcloneInstalled !== false
    needsSetup = parsed.needsSetup === true
    needsMount = parsed.needsMount === true
    needsAuth = parsed.needsAuth === true
    linger = parsed.linger === true
    unitScope = String(parsed.unitScope || "user")
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    if (_lingerDesired !== -1 && linger === (_lingerDesired === 1)) _lingerDesired = -1
    if (_desired === -1) _suppressNotify = false
    lastError = parsed.lastError || ""
  }

  function applyAbout(raw) {
    var parsed = Model.parseAbout(raw)
    if (!parsed.ok) {
      if (parsed.authHint === true && state === "healthy") {
        // Keep the mount state; surface the quota error only.
      }
      lastError = parsed.error || lastError
      return
    }
    usedBytes = parsed.usedBytes
    quotaBytes = parsed.quotaBytes
    freeBytes = parsed.freeBytes
    quotaKnown = parsed.quotaKnown === true
  }

  function toggleRunning() {
    if (active) stop()
    else start()
  }

  function start() { runControl("start", 1) }
  function stop() { runControl("stop", 0) }
  function restart() { runControl("restart", 1) }

  function toggleLinger() {
    if (lingerProcess.running) return
    setLinger(!lingerActive)
  }

  function setLinger(on) {
    if (lingerProcess.running || helperPath === "") return
    _lingerDesired = on ? 1 : 0
    _lingerOutput = ""
    _lingerError = ""
    actionStatus = on ? "Enabling mount at boot…" : "Disabling mount at boot…"
    lingerProcess.command = ["/usr/bin/python3", helperPath, on ? "linger-on" : "linger-off"].concat(helperArgs())
    lingerProcess.running = true
  }

  function runControl(verb, desired) {
    if (controlProcess.running || helperPath === "") return
    _desired = desired
    _suppressNotify = true
    _controlOutput = ""
    _controlError = ""
    actionStatus = verb === "stop" ? "Stopping mount…" : (verb === "restart" ? "Restarting mount…" : "Starting mount…")
    controlProcess.command = ["/usr/bin/python3", helperPath, verb].concat(helperArgs())
    controlProcess.running = true
  }

  function openMount() {
    openInFiles()
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function openInFiles() {
    if (!mountPath) return
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--new-window", String(mountPath)])
  }

  function openInTerminal() {
    if (!mountPath) return
    // Match omarchy-launch-terminal: setsid + uwsm-app + xdg-terminal-exec.
    // Launch after the popup releases exclusive keyboard focus, or Alacritty
    // often never maps.
    Quickshell.execDetached([
      "bash", "-lc",
      "setsid uwsm-app -- xdg-terminal-exec --dir=" + shellQuote(String(mountPath))
    ])
  }

  function openFile(file) {
    if (!file) return
    var path = String(file.path || file.cachePath || "")
    if (path === "") return
    Quickshell.execDetached(["xdg-open", path])
  }

  function cancelSetup() {
    if (!setupProcess.running) return
    _setupCancelled = true
    setupProcess.running = false
  }

  function discardPending() {
    setupPending = false
    setupDomain = ""
    if (setupHelperPath === "") return
    Quickshell.execDetached(["/usr/bin/python3", setupHelperPath, "discard"])
  }

  function runSetup(kind) {
    if (setupHelperPath === "") return
    if (kind === "authorize" && setupProcess.running) {
      _setupRestart = "authorize"
      cancelSetup()
      return
    }
    if (setupProcess.running) return
    _setupOutput = ""
    _setupError = ""
    if (kind === "install-rclone") {
      actionStatus = "Opening rclone install…"
      setupProcess.command = ["/usr/bin/python3", setupHelperPath, "install-rclone"]
    } else if (kind === "reconnect") {
      actionStatus = "Complete sign-in in the browser…"
      setupProcess.command = ["/usr/bin/python3", setupHelperPath, "reconnect", "--account", setupAccount, "--remote", String(remote || setupRemote)]
    } else if (kind === "authorize") {
      actionStatus = "Complete sign-in in the browser…"
      setupProcess.command = ["/usr/bin/python3", setupHelperPath, "authorize", "--account", setupAccount]
    } else {
      actionStatus = "Creating mount…"
      setupProcess.command = [
        "/usr/bin/python3", setupHelperPath, "setup",
        "--account", setupAccount,
        "--remote", String(setupRemote || ""),
        "--mount", String(setting("mountPath", "") || "")
      ]
    }
    setupProcess.running = true
  }

  function removeRemote() {
    if (setupProcess.running || setupHelperPath === "") return
    var name = String(remote || setupRemote || "")
    if (name === "") {
      lastError = "No remote to remove"
      actionStatus = lastError
      return
    }
    _setupOutput = ""
    _setupError = ""
    actionStatus = "Removing " + name + "…"
    setupProcess.command = [
      "/usr/bin/python3", setupHelperPath, "remove",
      "--remote", name,
      "--mount", String(mountPath || ""),
      "--unit", String(unit || "")
    ]
    setupProcess.running = true
  }

  function maybeNotify(prev, next) {
    if (prev === "" || prev === next) return
    if (_suppressNotify) return
    if (prev === "healthy" && next !== "healthy") {
      Quickshell.execDetached([
        "notify-send", "-a", "OneDrive", "-u", "critical",
        "OneDrive disconnected", statusMessage(next)
      ])
    } else if (next === "healthy" && prev !== "healthy") {
      Quickshell.execDetached([
        "notify-send", "-a", "OneDrive",
        "OneDrive connected", remote + " is mounted again"
      ])
    }
  }

  function statusMessage(value) {
    if (value === "stale") return "The rclone mount is stale or not responding"
    if (value === "failed") return (unit || "rclone") + " failed"
    if (value === "unauthenticated") return "OneDrive needs rclone config reconnect"
    if (value === "stopped") return "The OneDrive mount is stopped"
    return "OneDrive is not connected"
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: aboutTimer
    interval: root.aboutIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: root.refreshAbout()
  }

  Timer {
    id: settleTimer
    property int ticks: 0
    interval: 1500
    repeat: true
    running: false
    onTriggered: {
      settleTimer.ticks += 1
      root.refresh()
      if (settleTimer.ticks >= 6) {
        settleTimer.ticks = 0
        settleTimer.running = false
        root._desired = -1
      }
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2400
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (stdout.trim() !== "") root.applyStatus(stdout)
      else root.lastError = root.elide(stderr || "Could not read OneDrive status")
    }
  }

  Process {
    id: aboutProcess
    running: false
    command: []
    stdout: StdioCollector { id: aboutStdout; waitForEnd: true; onStreamFinished: root._aboutOutput = text }
    stderr: StdioCollector { id: aboutStderr; waitForEnd: true; onStreamFinished: root._aboutError = text }
    onExited: function(exitCode) {
      root.aboutRefreshing = false
      var stdout = String(aboutStdout.text || root._aboutOutput || "")
      var stderr = String(aboutStderr.text || root._aboutError || "")
      if (stdout.trim() !== "") root.applyAbout(stdout)
      else if (stderr.trim() !== "") root.lastError = root.elide(stderr)
    }
  }

  Process {
    id: controlProcess
    running: false
    command: []
    stdout: StdioCollector { id: controlStdout; waitForEnd: true; onStreamFinished: root._controlOutput = text }
    stderr: StdioCollector { id: controlStderr; waitForEnd: true; onStreamFinished: root._controlError = text }
    onExited: function(exitCode) {
      var stdout = String(controlStdout.text || root._controlOutput || "")
      var stderr = String(controlStderr.text || root._controlError || "")
      var parsed = Model.parseAction(stdout)
      if (exitCode !== 0 || parsed.ok === false) {
        root._desired = -1
        root.lastError = root.elide(parsed.error || stderr || stdout || "Mount command failed")
        root.actionStatus = root.lastError
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      actionStatusTimer.restart()
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
    }
  }

  Process {
    id: setupProcess
    running: false
    command: []
    stdout: StdioCollector { id: setupStdout; waitForEnd: true; onStreamFinished: root._setupOutput = text }
    stderr: StdioCollector { id: setupStderr; waitForEnd: true; onStreamFinished: root._setupError = text }
    onExited: function(exitCode) {
      if (root._setupCancelled) {
        root._setupCancelled = false
        if (root._setupRestart !== "") {
          var restart = root._setupRestart
          root._setupRestart = ""
          Qt.callLater(function() { root.runSetup(restart) })
        }
        return
      }
      var stdout = String(setupStdout.text || root._setupOutput || "")
      var stderr = String(setupStderr.text || root._setupError || "")
      var parsed = Model.parseAction(stdout)
      if (exitCode !== 0 || parsed.ok === false) {
        root.lastError = root.elide(parsed.error || stderr || stdout || "Setup failed")
        root.actionStatus = root.lastError
      } else if (parsed.action === "remove") {
        root.lastError = ""
        root.actionStatus = "Remote removed"
        root.remote = ""
        root.mountPath = ""
        root.unit = ""
        root.running = false
        root.mounted = false
        root.probeOk = false
        root.files = []
        root.transferring = []
        root.needsSetup = true
        root.needsAuth = false
        root.needsMount = false
        root.setupRemote = ""
        root.setupPending = false
        root.setupDomain = ""
        root.state = "stopped"
        root.statusText = "Set up rclone"
      } else if (parsed.action === "authorized") {
        root.lastError = ""
        root.setupDomain = String(parsed.domain || "")
        if (parsed.suggestedRemote) root.setupRemote = String(parsed.suggestedRemote)
        root.setupPending = true
        root.actionStatus = root.setupRemote !== ""
          ? "Signed in. Remote name is " + root.setupRemote
          : "Signed in. Name this remote, then create the mount"
      } else {
        root.lastError = ""
        root.setupPending = false
        root.actionStatus = parsed.action === "reconnect" ? "Signed in" : "OneDrive is ready"
        if (parsed.remote) root.remote = String(parsed.remote)
        if (parsed.mount) root.mountPath = String(parsed.mount)
        if (parsed.unit) root.unit = String(parsed.unit)
      }
      actionStatusTimer.restart()
      settleTimer.ticks = 0
      settleTimer.restart()
      root.refresh()
      root.refreshAbout()
    }
  }

  Process {
    id: lingerProcess
    running: false
    command: []
    stdout: StdioCollector { id: lingerStdout; waitForEnd: true; onStreamFinished: root._lingerOutput = text }
    stderr: StdioCollector { id: lingerStderr; waitForEnd: true; onStreamFinished: root._lingerError = text }
    onExited: function(exitCode) {
      var stdout = String(lingerStdout.text || root._lingerOutput || "")
      var stderr = String(lingerStderr.text || root._lingerError || "")
      var parsed = Model.parseAction(stdout)
      if (exitCode !== 0 || parsed.ok === false) {
        root._lingerDesired = -1
        root.lastError = root.elide(parsed.error || stderr || stdout || "Could not change boot mount")
        root.actionStatus = root.lastError
      } else {
        root.lastError = ""
        root.linger = parsed.linger === true
        root._lingerDesired = -1
        root.actionStatus = root.linger ? "Mounts at boot" : "Mounts after login"
      }
      actionStatusTimer.restart()
      root.refresh()
    }
  }
}
