function defaultStatus() {
  return {
    ok: true,
    nowMs: Date.now(),
    remote: "",
    mountPath: "",
    unit: "",
    state: "stopped",
    statusText: "Checking…",
    running: false,
    loaded: false,
    activeState: "",
    subState: "",
    result: "",
    restarts: 0,
    startedMs: 0,
    startedText: "",
    mounted: false,
    mountSource: "",
    probeOk: false,
    rcAvailable: false,
    speed: 0,
    errors: 0,
    transferring: [],
    cacheFiles: 0,
    cacheBytes: 0,
    files: [],
    excludeNote: "Personal Vault excluded",
    lastJournal: "",
    authHint: false,
    rcloneInstalled: true,
    needsSetup: false,
    needsMount: false,
    needsAuth: false,
    lastError: ""
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") {
    var empty = defaultStatus()
    empty.ok = false
    empty.lastError = "No mount status"
    return empty
  }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") {
      var bad = defaultStatus()
      bad.ok = false
      bad.lastError = "Invalid mount status"
      return bad
    }
    parsed.ok = parsed.ok !== false
    parsed.transferring = Array.isArray(parsed.transferring) ? parsed.transferring : []
    parsed.files = Array.isArray(parsed.files) ? parsed.files : []
    parsed.lastError = String(parsed.lastError || "")
    return parsed
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.lastError = "Failed to parse mount status"
    return failed
  }
}

function parseAbout(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "No quota data", quotaKnown: false }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return { ok: false, error: "Invalid quota data", quotaKnown: false }
    parsed.ok = parsed.ok !== false
    parsed.error = String(parsed.error || "")
    parsed.usedBytes = Number(parsed.usedBytes || 0)
    parsed.quotaBytes = Number(parsed.quotaBytes || 0)
    parsed.freeBytes = Number(parsed.freeBytes || 0)
    parsed.trashedBytes = Number(parsed.trashedBytes || 0)
    parsed.quotaKnown = parsed.quotaKnown === true
    parsed.authHint = parsed.authHint === true
    return parsed
  } catch (e) {
    return { ok: false, error: "Failed to parse quota", quotaKnown: false }
  }
}

function parseAction(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "No response" }
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object") return { ok: false, error: "Invalid response" }
    return parsed
  } catch (e) {
    return { ok: false, error: "Failed to parse response" }
  }
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value < 0) return "0 B"
  if (value === 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2)
  return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index]
}

function usageText(usedBytes, quotaBytes, quotaKnown) {
  if (quotaKnown && Number(quotaBytes || 0) > 0) {
    return formatBytes(usedBytes) + " of " + formatBytes(quotaBytes)
  }
  if (Number(usedBytes || 0) > 0) return formatBytes(usedBytes)
  return "Unknown"
}

function formatSpeed(bytesPerSec) {
  var value = Number(bytesPerSec || 0)
  if (!isFinite(value) || value <= 0) return ""
  return formatBytes(value) + "/s"
}

function relativeTime(timestampSec, nowMs) {
  var ts = Number(timestampSec || 0)
  if (!isFinite(ts) || ts <= 0) return "Unknown time"
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - ts * 1000) / 1000))
  if (diff < 60) return "Just now"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  var months = Math.floor(days / 30)
  if (months < 12) return months + "mo ago"
  return Math.floor(days / 365) + "y ago"
}

function uptimeText(startedMs, nowMs) {
  var start = Number(startedMs || 0)
  if (!isFinite(start) || start <= 0) return "—"
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - start) / 1000))
  if (diff < 60) return diff + "s"
  var minutes = Math.floor(diff / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  var remMin = minutes % 60
  if (hours < 48) return remMin ? hours + "h " + remMin + "m" : hours + "h"
  var days = Math.floor(hours / 24)
  return days + "d"
}

function fileExtension(name) {
  var value = String(name || "").toLowerCase()
  var index = value.lastIndexOf(".")
  return index >= 0 ? value.substring(index + 1) : ""
}

function fileGlyph(name) {
  var ext = fileExtension(name)
  if ("jpg jpeg png gif webp avif heic svg bmp tif tiff".split(" ").indexOf(ext) >= 0) return "󰋩"
  if ("mp4 mov mkv webm avi m4v mpg mpeg wmv".split(" ").indexOf(ext) >= 0) return "󰈫"
  if ("pdf txt md doc docx xls xlsx ppt pptx odt ods odp rtf csv html".split(" ").indexOf(ext) >= 0) return "󰈙"
  return "󰈔"
}

function fileMeta(file, nowMs) {
  if (!file) return ""
  var parts = [relativeTime(file.modifiedTs, nowMs)]
  var folder = String(file.folder || "")
  if (folder !== "" && folder !== "/") parts.push(folder)
  if (file.sizeBytes) parts.push(formatBytes(file.sizeBytes))
  return parts.join(" · ")
}

function transferMeta(file) {
  if (!file) return ""
  var size = Number(file.sizeBytes || 0)
  var done = Number(file.bytes || 0)
  if (size > 0) return formatBytes(done) + " of " + formatBytes(size)
  return formatBytes(done)
}

function stateReason(status) {
  if (!status) return "Unknown"
  if (status.statusText) return String(status.statusText)
  return String(status.state || "Unknown")
}

function alarming(state) {
  return state === "failed" || state === "stale" || state === "unauthenticated"
}

function tooltip(status) {
  if (!status) return "OneDrive"
  var line = String(status.remote || "OneDrive") + " · " + stateReason(status)
  if (status.transferring && status.transferring.length > 0) {
    line += " · " + status.transferring[0].name
  }
  return line
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultStatus: defaultStatus,
    parseStatus: parseStatus,
    parseAbout: parseAbout,
    parseAction: parseAction,
    formatBytes: formatBytes,
    usageText: usageText,
    formatSpeed: formatSpeed,
    relativeTime: relativeTime,
    uptimeText: uptimeText,
    fileGlyph: fileGlyph,
    fileMeta: fileMeta,
    transferMeta: transferMeta,
    stateReason: stateReason,
    alarming: alarming,
    tooltip: tooltip
  }
}
