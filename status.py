#!/usr/bin/python3
"""OneDrive / rclone mount status for the jason.rclone-onedrive Omarchy widget.

Fast path never talks to OneDrive and never walks the FUSE mount. Quota is a
separate `about` subcommand. start/stop/restart use systemctl --user when the
unit is a user unit, otherwise pkexec systemctl.
"""

from __future__ import annotations

import argparse
import heapq
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

DEFAULT_RC = "http://127.0.0.1:5572"
RCLONE_BIN = "/home/jason/.local/bin/rclone"

AUTH_RE = re.compile(
    r"401|unauthoriz|unauthenticat|invalid_grant|token expired|"
    r"expired_token|couldn.t fetch token|refresh.?token|oauth",
    re.I,
)
NOISE_RE = re.compile(r"vfs cache:\s*cleaned", re.I)
INTERESTING_RE = re.compile(
    r"\bERROR\b|\berror\b|failed|fatal|401|unauthoriz|unauthenticat|"
    r"invalid_grant|token|oauth|couldn't|vfs cache: downloaded|copied|"
    r"updated|transferred",
    re.I,
)


def run(cmd: list[str], timeout: float) -> tuple[int, str, str]:
    try:
        completed = subprocess.run(
            cmd, check=False, capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except OSError as exc:
        return 1, "", str(exc)
    return completed.returncode, completed.stdout, completed.stderr


def rclone_bin() -> str:
    found = shutil.which("rclone")
    if found:
        return found
    if Path(RCLONE_BIN).is_file():
        return RCLONE_BIN
    return "rclone"


def onedrive_remotes() -> list[str]:
    code, stdout, _stderr = run([rclone_bin(), "config", "dump"], timeout=2.0)
    if code != 0:
        return []
    try:
        parsed = json.loads(stdout)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, dict):
        return []
    names: list[str] = []
    for name, cfg in parsed.items():
        if isinstance(cfg, dict) and cfg.get("type") == "onedrive":
            names.append(str(name))
    return names


def rclone_mounts() -> list[tuple[str, str]]:
    code, stdout, _stderr = run(
        ["findmnt", "-t", "fuse.rclone", "-n", "-o", "SOURCE,TARGET"], timeout=1.5
    )
    rows: list[tuple[str, str]] = []
    if code != 0:
        return rows
    for line in stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        rows.append((parts[0].rstrip(":"), parts[1]))
    return rows


def unit_exec(unit: str, user: bool) -> str:
    cmd = ["systemctl"]
    if user:
        cmd.append("--user")
    cmd += ["show", unit, "-p", "ExecStart", "-p", "FragmentPath"]
    _code, stdout, _stderr = run(cmd, timeout=2.0)
    return stdout


def list_rclone_units() -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    seen: set[str] = set()
    for user, flag in ((False, []), (True, ["--user"])):
        code, stdout, _stderr = run(
            ["systemctl", *flag, "list-unit-files", "--type=service", "--no-legend", "--plain"],
            timeout=2.0,
        )
        if code != 0:
            continue
        for line in stdout.splitlines():
            name = (line.split() or [""])[0]
            if "rclone" not in name.lower() or name in seen:
                continue
            seen.add(name)
            found.append((name, "user" if user else "system"))
    return found


def match_unit(remote: str, mount: str) -> tuple[str, str]:
    remote_key = remote.rstrip(":")
    for unit, scope in list_rclone_units():
        blob = unit_exec(unit, scope == "user")
        if remote_key and remote_key + ":" in blob:
            return unit, scope
        if mount and mount in blob:
            return unit, scope
        if remote_key and remote_key in unit:
            return unit, scope
    return "", "system"


def exclude_note_from_unit(unit: str, scope: str) -> str:
    if not unit:
        return ""
    blob = unit_exec(unit, scope == "user")
    if "Personal Vault" in blob:
        return "Personal Vault excluded"
    return ""


def resolve(args: argparse.Namespace) -> argparse.Namespace:
    remotes = onedrive_remotes()
    mounts = rclone_mounts()
    if not args.remote:
        if remotes:
            args.remote = remotes[0]
        elif mounts:
            args.remote = mounts[0][0]
    remote = str(args.remote or "").rstrip(":")
    args.remote = remote
    if not args.mount:
        for src, target in mounts:
            if not remote or src.rstrip(":") == remote:
                args.mount = target
                break
    if not args.unit:
        args.unit, args.unit_scope = match_unit(remote, str(args.mount or ""))
    else:
        args.unit_scope = "user" if str(getattr(args, "unit_scope", "")) == "user" else ""
        if not args.unit_scope:
            user_names = {name for name, scope in list_rclone_units() if scope == "user"}
            args.unit_scope = "user" if args.unit in user_names else "system"
    if not args.vfs and remote:
        args.vfs = str(Path.home() / ".cache" / "rclone" / "vfs" / remote)
    if not args.rc:
        args.rc = DEFAULT_RC
    return args


def parse_show(text: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        out[key] = value
    return out


def unix_timestamp_ms(value: str) -> int:
    text = str(value or "").strip().lstrip("@")
    try:
        number = int(text)
    except (TypeError, ValueError):
        return 0
    if number <= 0:
        return 0
    if number > 10**12:
        return number
    return number * 1000


def rclone_installed() -> bool:
    found = shutil.which("rclone")
    return bool(found or Path(RCLONE_BIN).is_file())


def unit_status(unit: str) -> dict:
    empty = {
        "loaded": False,
        "running": False,
        "activeState": "inactive",
        "subState": "",
        "result": "",
        "restarts": 0,
        "startedMs": 0,
        "startedText": "",
        "error": "",
    }
    if not unit:
        return empty
    code, stdout, stderr = run(
        [
            "systemctl",
            "show",
            "--timestamp=unix",
            unit,
            "-p",
            "LoadState",
            "-p",
            "ActiveState",
            "-p",
            "SubState",
            "-p",
            "Result",
            "-p",
            "NRestarts",
            "-p",
            "ExecMainStartTimestamp",
            "-p",
            "ActiveEnterTimestamp",
        ],
        timeout=2.0,
    )
    fields = parse_show(stdout)
    loaded = fields.get("LoadState", "") == "loaded"
    active_state = fields.get("ActiveState", "")
    running = active_state == "active"
    started_ms = unix_timestamp_ms(
        fields.get("ExecMainStartTimestamp") or fields.get("ActiveEnterTimestamp") or ""
    )
    try:
        restarts = int(fields.get("NRestarts") or 0)
    except ValueError:
        restarts = 0
    return {
        "loaded": loaded,
        "running": running,
        "activeState": active_state or "unknown",
        "subState": fields.get("SubState") or "",
        "result": fields.get("Result") or "",
        "restarts": restarts,
        "startedMs": started_ms,
        "startedText": fields.get("ExecMainStartTimestamp") or "",
        "error": "" if code == 0 else (stderr or stdout or "systemctl show failed"),
    }


def mount_present(mount_path: str) -> tuple[bool, str]:
    code, stdout, _stderr = run(
        ["findmnt", "-n", "-o", "SOURCE,FSTYPE", mount_path], timeout=1.5
    )
    line = stdout.strip()
    if code != 0 or not line:
        return False, ""
    return True, line


def probe_mount(mount_path: str) -> bool:
    code, _stdout, _stderr = run(
        ["timeout", "2", "stat", "-c", "%F", mount_path], timeout=2.5
    )
    return code == 0


def rc_json(rc_url: str, method: str) -> tuple[bool, dict]:
    code, stdout, _stderr = run(
        [rclone_bin(), "rc", "--url", rc_url, method], timeout=1.5
    )
    if code != 0:
        return False, {}
    try:
        parsed = json.loads(stdout)
    except json.JSONDecodeError:
        return False, {}
    return isinstance(parsed, dict), parsed if isinstance(parsed, dict) else {}


def transferring_rows(stats: dict) -> list[dict]:
    rows: list[dict] = []
    raw = stats.get("transferring") or []
    if not isinstance(raw, list):
        return rows
    for item in raw:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or item.get("srcFs") or "")
        if not name:
            continue
        rows.append(
            {
                "name": Path(name).name,
                "path": name,
                "bytes": int(item.get("bytes") or 0),
                "sizeBytes": int(item.get("size") or 0),
                "percent": float(item.get("percentage") or 0),
            }
        )
    return rows


def vfs_cache_rows(vfs_root: str, mount_path: str, limit: int) -> tuple[int, int, list[dict]]:
    root = Path(vfs_root).expanduser()
    mount = Path(mount_path)
    try:
        resolved_root = root.resolve()
        resolved_mount = mount.resolve()
    except OSError:
        return 0, 0, []
    if resolved_root == resolved_mount:
        return 0, 0, []
    if not root.is_dir():
        return 0, 0, []

    recent: list[tuple[int, int, dict]] = []
    counter = 0
    total_bytes = 0
    try:
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            dirnames[:] = [
                name
                for name in dirnames
                if not os.path.islink(os.path.join(dirpath, name))
            ]
            for name in filenames:
                file_path = Path(dirpath) / name
                if file_path.is_symlink():
                    continue
                try:
                    stat = file_path.stat()
                except OSError:
                    continue
                total_bytes += stat.st_size
                rel = file_path.relative_to(root)
                folder = str(rel.parent)
                if folder in (".", ""):
                    folder = "/"
                row = {
                    "name": name,
                    "cachePath": str(file_path),
                    "path": str(mount / rel),
                    "folder": folder,
                    "modifiedTs": int(stat.st_mtime),
                    "sizeBytes": stat.st_size,
                }
                counter += 1
                entry = (row["modifiedTs"], counter, row)
                if len(recent) < limit:
                    heapq.heappush(recent, entry)
                else:
                    heapq.heappushpop(recent, entry)
    except OSError:
        return 0, 0, []

    rows = [item[2] for item in sorted(recent, reverse=True)]
    return counter, total_bytes, rows


def journal_hint(unit: str) -> tuple[str, bool]:
    if not unit:
        return "", False
    code, stdout, _stderr = run(
        ["journalctl", "-u", unit, "-n", "80", "--no-pager", "-o", "cat"],
        timeout=2.0,
    )
    if code != 0:
        return "", False
    last = ""
    auth = False
    for raw in stdout.splitlines():
        line = raw.strip()
        if not line or NOISE_RE.search(line):
            continue
        if not INTERESTING_RE.search(line):
            continue
        last = line
        if AUTH_RE.search(line):
            auth = True
    return last[:280], auth


def derive_state(
    unit: dict, mounted: bool, probe_ok: bool, auth_hint: bool
) -> str:
    failed = (not unit["running"] and unit["result"] == "failed") or unit[
        "activeState"
    ] == "failed"
    if failed:
        return "unauthenticated" if auth_hint else "failed"
    if not unit["running"]:
        return "unauthenticated" if auth_hint else "stopped"
    if not mounted or not probe_ok:
        return "unauthenticated" if auth_hint else "stale"
    return "healthy"


def emit(payload: dict) -> int:
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0 if payload.get("ok", True) else 1


def cmd_status(args: argparse.Namespace) -> int:
    now_ms = int(time.time() * 1000)
    unit = unit_status(args.unit)
    mounted, mount_source = mount_present(args.mount)
    probe_ok = probe_mount(args.mount) if mounted or unit["running"] else False
    rc_ok, stats = rc_json(args.rc, "core/stats")
    vfs_ok, vfs_stats = rc_json(args.rc, "vfs/stats") if rc_ok else (False, {})
    transferring = transferring_rows(stats) if rc_ok else []
    cache_files, cache_bytes, files = vfs_cache_rows(args.vfs, args.mount, 15)
    last_journal, auth_hint = journal_hint(args.unit)
    disk_cache = vfs_stats.get("diskCache") if isinstance(vfs_stats, dict) else {}
    if not isinstance(disk_cache, dict):
        disk_cache = {}

    state = derive_state(unit, mounted, probe_ok, auth_hint)
    has_remote = bool(args.remote)
    installed = rclone_installed()
    needs_setup = (not installed) or (not has_remote)
    needs_mount = has_remote and not bool(args.unit) and not mounted
    needs_auth = state == "unauthenticated"
    if needs_setup and not has_remote:
        status_text = "Needs setup"
        if not installed:
            status_text = "rclone missing"
        state = "setup"
    else:
        status_text = {
        "healthy": "Connected",
        "stopped": "Mount stopped",
        "failed": "Mount failed",
        "stale": "Mount stale",
        "unauthenticated": "Needs reauth",
    }.get(state, state)

    speed = float(stats.get("speed") or 0) if rc_ok else 0.0
    errors = int(stats.get("errors") or 0) if rc_ok else 0
    rc_cache_bytes = int(disk_cache.get("bytesUsed") or 0)
    rc_cache_files = int(disk_cache.get("files") or 0)

    return emit(
        {
            "ok": True,
            "nowMs": now_ms,
            "remote": args.remote,
            "mountPath": args.mount,
            "unit": args.unit,
            "state": state,
            "statusText": status_text,
            "running": unit["running"],
            "loaded": unit["loaded"],
            "activeState": unit["activeState"],
            "subState": unit["subState"],
            "result": unit["result"],
            "restarts": unit["restarts"],
            "startedMs": unit["startedMs"],
            "startedText": unit["startedText"],
            "mounted": mounted,
            "mountSource": mount_source,
            "probeOk": probe_ok,
            "rcAvailable": rc_ok,
            "speed": speed,
            "errors": errors,
            "transferring": transferring,
            "cacheFiles": rc_cache_files or cache_files,
            "cacheBytes": rc_cache_bytes or cache_bytes,
            "files": files,
            "unitScope": getattr(args, "unit_scope", "system"),
            "excludeNote": exclude_note_from_unit(
                args.unit, getattr(args, "unit_scope", "system")
            ),
            "lastJournal": last_journal,
            "authHint": auth_hint,
            "rcloneInstalled": installed,
            "needsSetup": needs_setup,
            "needsMount": needs_mount,
            "needsAuth": needs_auth,
            "lastError": unit["error"],
        }
    )


def parse_about_json(raw: str) -> dict:
    parsed = json.loads(raw)
    if not isinstance(parsed, dict):
        raise ValueError("not an object")
    return {
        "usedBytes": int(parsed.get("used") or 0),
        "quotaBytes": int(parsed.get("total") or 0),
        "freeBytes": int(parsed.get("free") or 0),
        "trashedBytes": int(parsed.get("trashed") or 0),
        "quotaKnown": int(parsed.get("total") or 0) > 0,
    }


def cmd_about(args: argparse.Namespace) -> int:
    if not args.remote:
        return emit(
            {
                "ok": False,
                "authHint": False,
                "error": "No OneDrive remote yet",
                "usedBytes": 0,
                "quotaBytes": 0,
                "freeBytes": 0,
                "trashedBytes": 0,
                "quotaKnown": False,
            }
        )
    remote = args.remote if args.remote.endswith(":") else f"{args.remote}:"
    code, stdout, stderr = run(
        [rclone_bin(), "about", remote, "--json"], timeout=25.0
    )
    if code != 0:
        text = (stderr or stdout or "rclone about failed").strip()
        auth = bool(AUTH_RE.search(text))
        return emit(
            {
                "ok": False,
                "authHint": auth,
                "error": text[:280],
                "usedBytes": 0,
                "quotaBytes": 0,
                "freeBytes": 0,
                "trashedBytes": 0,
                "quotaKnown": False,
            }
        )
    try:
        quota = parse_about_json(stdout)
    except (ValueError, json.JSONDecodeError, TypeError):
        return emit(
            {
                "ok": False,
                "authHint": False,
                "error": "Failed to parse rclone about",
                "usedBytes": 0,
                "quotaBytes": 0,
                "freeBytes": 0,
                "trashedBytes": 0,
                "quotaKnown": False,
            }
        )
    quota.update({"ok": True, "authHint": False, "error": ""})
    return emit(quota)


def cmd_control(args: argparse.Namespace) -> int:
    verb = args.command
    if not args.unit:
        return emit({"ok": False, "action": verb, "error": "No rclone unit found"})
    if getattr(args, "unit_scope", "system") == "user":
        command = ["systemctl", "--user", verb, args.unit]
    else:
        command = ["pkexec", "systemctl", verb, args.unit]
    code, stdout, stderr = run(command, timeout=30.0)
    if code != 0:
        return emit(
            {
                "ok": False,
                "action": verb,
                "error": (stderr or stdout or f"systemctl {verb} failed").strip()[
                    :280
                ],
            }
        )
    return emit({"ok": True, "action": verb, "error": ""})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remote", default="")
    parser.add_argument("--mount", default="")
    parser.add_argument("--unit", default="")
    parser.add_argument("--rc", default=DEFAULT_RC)
    parser.add_argument("--vfs", default="")
    parser.add_argument(
        "command",
        nargs="?",
        default="status",
        choices=["status", "about", "start", "stop", "restart"],
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    resolve(args)
    if args.command == "status":
        return cmd_status(args)
    if args.command == "about":
        return cmd_about(args)
    return cmd_control(args)


if __name__ == "__main__":
    sys.exit(main())
