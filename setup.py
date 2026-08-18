#!/usr/bin/python3
"""First-run OneDrive setup for jason.rclone-onedrive.

Walks rclone's non-interactive config protocol, signs in at the matching
Microsoft endpoint (consumers vs organizations), then writes a user systemd
mount unit. Never prints tokens.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

RCLONE_BIN = "/home/jason/.local/bin/rclone"
URL_RE = re.compile(r"https?://[^\s\"'<>]+")
TOKEN_RE = re.compile(r"\{[^{}]*\"access_token\"[^{}]*\}", re.S)

LOGIN_HOST = {
    "global": "login.microsoftonline.com",
    "us": "login.microsoftonline.us",
    "cn": "login.partner.microsoftonline.cn",
    "de": "login.microsoftonline.com",
}


def emit(payload: dict) -> int:
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0 if payload.get("ok", True) else 1


def fail(error: str, **extra) -> int:
    payload = {"ok": False, "error": error[:400]}
    payload.update(extra)
    return emit(payload)


def rclone_bin() -> str:
    found = shutil.which("rclone")
    if found:
        return found
    if Path(RCLONE_BIN).is_file():
        return RCLONE_BIN
    return ""


def endpoints(account: str, region: str) -> dict[str, str]:
    host = LOGIN_HOST.get(region, LOGIN_HOST["global"])
    tenant = "consumers" if account == "personal" else "organizations"
    return {
        "auth_url": f"https://{host}/{tenant}/oauth2/v2.0/authorize",
        "token_url": f"https://{host}/{tenant}/oauth2/v2.0/token",
        "config_type": "onedrive",
        "drive_type": {
            "personal": "personal",
            "business": "business",
            "sharepoint": "documentLibrary",
        }.get(account, "personal"),
    }


def open_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return
    subprocess.Popen(
        ["xdg-open", url],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def kill_stale_auth_server() -> None:
    subprocess.run(
        ["fuser", "-k", "53682/tcp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=3,
    )
    subprocess.run(
        ["pkill", "-f", r"rclone authorize onedrive"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=3,
    )


def authorize(bin_path: str, auth_url: str, token_url: str) -> tuple[str, str]:
    kill_stale_auth_server()
    time.sleep(0.2)
    env = os.environ.copy()
    env["RCLONE_ONEDRIVE_AUTH_URL"] = auth_url
    env["RCLONE_ONEDRIVE_TOKEN_URL"] = token_url
    proc = subprocess.Popen(
        [bin_path, "authorize", "onedrive"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
        start_new_session=True,
    )

    def cleanup(*_args: object) -> None:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except OSError:
                proc.terminate()

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)
    opened = {"url": ""}
    err_lines: list[str] = []

    def pump_err() -> None:
        assert proc.stderr is not None
        for line in proc.stderr:
            err_lines.append(line.rstrip())
            match = URL_RE.search(line)
            if not match:
                continue
            candidate = match.group(0).rstrip(").,/")
            if "/auth" not in candidate and "login.microsoftonline" not in candidate:
                continue
            if "localhost" in candidate and "/auth" not in candidate:
                continue
            if not opened["url"]:
                opened["url"] = candidate

    err_thread = threading.Thread(target=pump_err, daemon=True)
    err_thread.start()
    deadline = time.time() + 300
    try:
        while proc.poll() is None and time.time() < deadline:
            time.sleep(0.2)
        if proc.poll() is None:
            cleanup()
            err_thread.join(timeout=1)
            return "", "Microsoft sign-in timed out"
        stdout = proc.stdout.read() if proc.stdout else ""
        err_thread.join(timeout=1)
        tail = " ".join(err_lines[-3:]).strip()
        if proc.returncode != 0:
            return "", tail or "Microsoft sign-in was cancelled or failed"
        blob = stdout or ""
        match = TOKEN_RE.search(blob)
        if match:
            return match.group(0), ""
        text = blob.strip()
        if text.startswith("{") and "access_token" in text:
            return text, ""
        return "", tail or "rclone authorize did not return a token"
    finally:
        cleanup()


def jwt_claims(token: str) -> dict:
    parts = token.split(".")
    if len(parts) < 2:
        return {}
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        data = json.loads(base64.urlsafe_b64decode(payload))
    except (ValueError, json.JSONDecodeError, OSError):
        return {}
    return data if isinstance(data, dict) else {}


def email_from_claims(claims: dict) -> str:
    for key in ("preferred_username", "upn", "unique_name", "email"):
        value = claims.get(key)
        if isinstance(value, str) and "@" in value:
            return value.strip()
    return ""


def email_from_token_blob(token_blob: str) -> str:
    try:
        data = json.loads(token_blob)
    except json.JSONDecodeError:
        return ""
    if not isinstance(data, dict):
        return ""
    for key in ("id_token", "access_token"):
        email = email_from_claims(jwt_claims(str(data.get(key) or "")))
        if email:
            return email
    access = str(data.get("access_token") or "")
    if not access:
        return ""
    try:
        req = Request(
            "https://graph.microsoft.com/v1.0/me?$select=userPrincipalName,mail",
            headers={"Authorization": f"Bearer {access}"},
        )
        with urlopen(req, timeout=8) as resp:
            me = json.loads(resp.read().decode("utf-8"))
    except (OSError, json.JSONDecodeError, ValueError):
        return ""
    if not isinstance(me, dict):
        return ""
    for key in ("userPrincipalName", "mail"):
        value = me.get(key)
        if isinstance(value, str) and "@" in value:
            return value.strip()
    return ""


def sanitize_remote(name: str) -> str:
    cleaned = (name or "").strip().lower().replace(".", "-")
    cleaned = re.sub(r"[^a-z0-9_-]+", "", cleaned)
    return cleaned.strip("-_")


def remote_from_email(email: str, taken: set[str]) -> str:
    if "@" not in (email or ""):
        return ""
    domain = email.rsplit("@", 1)[-1].lower().strip()
    base = sanitize_remote(domain)
    if not base:
        return ""
    name = base
    n = 2
    while name in taken:
        name = f"{base}-{n}"
        n += 1
    return name


def pending_path() -> Path:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")
    return runtime / "omarchy-rclone-onedrive-pending.json"


def save_pending(payload: dict) -> None:
    path = pending_path()
    path.write_text(json.dumps(payload), encoding="utf-8")
    path.chmod(0o600)


def load_pending() -> dict | None:
    path = pending_path()
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    created = float(data.get("created") or 0)
    if created and time.time() - created > 900:
        clear_pending()
        return None
    if not data.get("token"):
        return None
    return data


def clear_pending() -> None:
    path = pending_path()
    if path.is_file():
        path.unlink()


def ni(bin_path: str, name: str, extra: list[str]) -> dict:
    proc = subprocess.run(
        [bin_path, "config", "create", name, "onedrive", "--non-interactive", "--all", *extra],
        capture_output=True,
        text=True,
        timeout=30,
    )
    raw = (proc.stdout or "").strip()
    if raw.startswith("{"):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return {"Error": raw[:200], "State": ""}
    return {"Error": (proc.stderr or raw or "rclone config failed")[:200], "State": ""}


def pick_result(option: dict, account: str, ends: dict[str, str]) -> str:
    name = str(option.get("Name") or "")
    helptext = str(option.get("Help") or "")
    examples = option.get("Examples") or []
    default = option.get("DefaultStr")
    if default is None and option.get("Default") is not None:
        default = str(option.get("Default")).lower() if option.get("Type") == "bool" else str(option.get("Default"))
    default = "" if default is None else str(default)

    if name == "client_id":
        return ""
    if name == "client_secret":
        return ""
    if name == "region":
        return default or "global"
    if name == "tenant":
        return ""
    if name == "config_fs_advanced":
        return "false"
    if name == "config_is_local":
        return "false"
    if name == "config_type":
        return "onedrive"
    if name in ("config_driveid", "drive_id", "config_drive"):
        want = ends["drive_type"]
        for example in examples:
            help_line = str(example.get("Help") or "").lower()
            value = str(example.get("Value") or "")
            if want == "personal" and "personal" in help_line:
                return value
            if want == "business" and "business" in help_line:
                return value
            if want == "documentLibrary" and (
                "document" in help_line or "sharepoint" in help_line or "library" in help_line
            ):
                return value
        if examples:
            return str(examples[0].get("Value") or default)
        return default
    if name in ("config_drive_ok", "confirm") or "already exist" in helptext.lower():
        return "true"
    if option.get("Type") == "bool":
        return default or "false"
    return default


def create_remote(bin_path: str, name: str, account: str, region: str, token: str) -> str:
    ends = endpoints(account, region)
    extra = [
        "region",
        region,
        "auth_url",
        ends["auth_url"],
        "token_url",
        ends["token_url"],
    ]
    data = ni(bin_path, name, extra)
    for _ in range(24):
        state = data.get("State") or ""
        option = data.get("Option") or {}
        if data.get("Error") and not state:
            return str(data.get("Error"))
        if not state:
            return ""
        if option.get("Name") == "config_token":
            result = token
        else:
            result = pick_result(option, account, ends)
        data = ni(
            bin_path,
            name,
            extra + ["--continue", "--state", state, "--result", result],
        )
    return "rclone asked too many setup questions"


def write_user_unit(remote: str, mount: str, rc_url: str) -> tuple[str, str]:
    unit = f"rclone-{remote}.service"
    unit_path = Path.home() / ".config/systemd/user" / unit
    unit_path.parent.mkdir(parents=True, exist_ok=True)
    binary = rclone_bin()
    rc_addr = rc_url.replace("http://", "").replace("https://", "")
    body = f"""[Unit]
Description=rclone OneDrive mount ({remote})
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart={binary} mount {remote}: {mount} --vfs-cache-mode full --log-level INFO --rc --rc-addr {rc_addr} --rc-no-auth
ExecStop=/usr/bin/fusermount3 -uz {mount}
TimeoutStopSec=10
SuccessExitStatus=143
Restart=on-failure

[Install]
WantedBy=default.target
"""
    unit_path.write_text(body, encoding="utf-8")
    return unit, str(unit_path)


def stop_user_unit(unit: str, mount: str) -> None:
    subprocess.run(
        ["systemctl", "--user", "stop", unit],
        capture_output=True,
        text=True,
        timeout=15,
    )
    if mount:
        subprocess.run(
            ["/usr/bin/fusermount3", "-uz", mount],
            capture_output=True,
            text=True,
            timeout=5,
        )


def enable_user_unit(unit: str) -> str:
    for cmd in (
        ["systemctl", "--user", "daemon-reload"],
        ["systemctl", "--user", "enable", "--now", unit],
    ):
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if proc.returncode != 0:
            return (proc.stderr or proc.stdout or " ".join(cmd)).strip()[:280]
    return ""


def existing_remotes(bin_path: str) -> set[str]:
    proc = subprocess.run([bin_path, "listremotes"], capture_output=True, text=True, timeout=3)
    names = set()
    for line in (proc.stdout or "").splitlines():
        names.add(line.strip().rstrip(":"))
    return names


def find_mount(remote: str) -> str:
    proc = subprocess.run(
        ["findmnt", "-t", "fuse.rclone", "-n", "-o", "SOURCE,TARGET"],
        capture_output=True,
        text=True,
        timeout=3,
    )
    needle = remote.rstrip(":") + ":"
    for line in (proc.stdout or "").splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        if parts[0].rstrip(":") == remote or parts[0] == needle:
            return parts[1]
    return ""


def user_unit_path(unit: str) -> Path:
    return Path.home() / ".config" / "systemd" / "user" / unit


def disable_user_unit(unit: str) -> None:
    subprocess.run(
        ["systemctl", "--user", "disable", "--now", unit],
        capture_output=True,
        text=True,
        timeout=20,
    )
    path = user_unit_path(unit)
    if path.is_file():
        path.unlink()
    wants = Path.home() / ".config" / "systemd" / "user" / "default.target.wants" / unit
    if wants.is_symlink() or wants.is_file():
        wants.unlink()
    subprocess.run(
        ["systemctl", "--user", "daemon-reload"],
        capture_output=True,
        text=True,
        timeout=15,
    )


def delete_remote(bin_path: str, name: str) -> str:
    if name not in existing_remotes(bin_path):
        return ""
    proc = subprocess.run(
        [bin_path, "config", "delete", name],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if proc.returncode != 0:
        return (proc.stderr or proc.stdout or "rclone config delete failed").strip()[:280]
    return ""


def lazy_unmount(mount: str) -> None:
    if not mount:
        return
    try:
        subprocess.run(
            ["/usr/bin/fusermount3", "-uz", mount],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, OSError):
        pass


def cmd_remove(args: argparse.Namespace) -> int:
    try:
        return _cmd_remove(args)
    except Exception as exc:
        return fail(str(exc)[:280])


def _cmd_remove(args: argparse.Namespace) -> int:
    binary = rclone_bin()
    if not binary:
        return fail("rclone is not installed")
    remote = re.sub(r"[^A-Za-z0-9_-]+", "", args.remote or "")
    if not remote:
        return fail("No remote to remove")
    mount = str(Path(args.mount).expanduser()) if args.mount else find_mount(remote)
    unit = getattr(args, "unit", "") or f"rclone-{remote}.service"
    # Detach FUSE first so systemctl stop does not hang on a busy mount.
    lazy_unmount(mount)
    leftover = find_mount(remote)
    lazy_unmount(leftover)
    try:
        stop_user_unit(unit, mount or leftover)
    except (subprocess.TimeoutExpired, OSError):
        pass
    try:
        if user_unit_path(unit).is_file() or unit.startswith("rclone-"):
            disable_user_unit(unit)
    except (subprocess.TimeoutExpired, OSError):
        pass
    error = delete_remote(binary, remote)
    if error:
        return fail(error, remote=remote, mount=mount, unit=unit)
    clear_pending()
    return emit(
        {
            "ok": True,
            "action": "remove",
            "remote": remote,
            "mount": mount,
            "unit": unit,
            "error": "",
        }
    )


def cmd_setup(args: argparse.Namespace) -> int:
    binary = rclone_bin()
    if not binary:
        return fail("rclone is not installed")
    account = args.account
    region = args.region or "global"
    requested = sanitize_remote(args.remote or "")
    remotes = existing_remotes(binary)
    if requested and requested in remotes and not args.reconnect:
        return fail(f"rclone remote {requested} already exists")
    mount = str(Path(args.mount or (Path.home() / "OneDrive")).expanduser())
    Path(mount).mkdir(parents=True, exist_ok=True)
    ends = endpoints(account, region)
    pending = None if args.reconnect else load_pending()
    if pending and not requested:
        return fail("Give this remote a name")
    if pending:
        token = str(pending.get("token") or "")
        if not token:
            clear_pending()
            return fail("Sign-in expired. Sign in again.")
        remote = requested or sanitize_remote(str(pending.get("suggestedRemote") or ""))
        if not remote:
            return fail("Give this remote a name")
        if remote in remotes:
            return fail(f"rclone remote {remote} already exists")
        account = str(pending.get("account") or account)
        region = str(pending.get("region") or region)
        clear_pending()
        error = create_remote(binary, remote, account, region, token)
        if error:
            return fail(error)
        unit, _path = write_user_unit(remote, mount, args.rc)
        error = enable_user_unit(unit)
        if error:
            return fail(error, remote=remote, mount=mount, unit=unit)
        for _ in range(8):
            time.sleep(0.4)
            check = subprocess.run(
                ["findmnt", "-n", mount], capture_output=True, text=True, timeout=2
            )
            if check.returncode == 0:
                break
        return emit(
            {
                "ok": True,
                "action": "setup",
                "remote": remote,
                "mount": mount,
                "unit": unit,
                "account": account,
                "error": "",
            }
        )
    if not args.reconnect:
        return fail("Sign in with Microsoft first")
    if args.reconnect:
        remote = requested
        if not remote or remote not in remotes:
            return fail("No existing remote to reconnect")
        unit = f"rclone-{remote}.service"
        stop_user_unit(unit, mount)
        proc = subprocess.run(
            [
                binary,
                "config",
                "update",
                remote,
                "token",
                token,
                "config_refresh_token",
                "false",
            ],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if proc.returncode != 0:
            return fail((proc.stderr or proc.stdout or "token update failed").strip())
        error = enable_user_unit(unit)
        if error:
            return fail(error, remote=remote, mount=mount, unit=unit)
        return emit(
            {
                "ok": True,
                "action": "reconnect",
                "remote": remote,
                "mount": mount,
                "unit": unit,
                "error": "",
            }
        )
    return fail("Sign in again to continue setup")


def cmd_discard() -> int:
    clear_pending()
    return emit({"ok": True, "action": "discard", "error": ""})


def cmd_authorize(args: argparse.Namespace) -> int:
    binary = rclone_bin()
    if not binary:
        return fail("rclone is not installed")
    clear_pending()
    account = args.account
    region = args.region or "global"
    remotes = existing_remotes(binary)
    ends = endpoints(account, region)
    token, error = authorize(binary, ends["auth_url"], ends["token_url"])
    if error:
        return fail(error)
    email = email_from_token_blob(token)
    suggested = remote_from_email(email, remotes)
    domain = email.rsplit("@", 1)[-1].lower() if "@" in email else ""
    save_pending(
        {
            "created": time.time(),
            "account": account,
            "region": region,
            "token": token,
            "suggestedRemote": suggested,
            "domain": domain,
        }
    )
    return emit(
        {
            "ok": True,
            "action": "authorized",
            "suggestedRemote": suggested,
            "domain": domain,
            "error": "",
        }
    )


def cmd_install_rclone() -> int:
    launcher = shutil.which("omarchy-launch-floating-terminal-with-presentation")
    pkg = shutil.which("omarchy-pkg-add") or "omarchy"
    if launcher:
        subprocess.Popen(
            [launcher, "omarchy pkg add rclone"],
            start_new_session=True,
        )
        return emit({"ok": True, "action": "install-rclone", "error": ""})
    proc = subprocess.run([pkg, "pkg", "add", "rclone"], capture_output=True, text=True)
    if proc.returncode != 0:
        return fail((proc.stderr or proc.stdout or "could not install rclone").strip())
    return emit({"ok": True, "action": "install-rclone", "error": ""})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        nargs="?",
        default="setup",
        choices=["setup", "authorize", "discard", "reconnect", "install-rclone", "remove"],
    )
    parser.add_argument("--account", default="personal", choices=["personal", "business", "sharepoint"])
    parser.add_argument("--region", default="global")
    parser.add_argument("--remote", default="")
    parser.add_argument("--mount", default="")
    parser.add_argument("--unit", default="")
    parser.add_argument("--rc", default="http://127.0.0.1:5572")
    parser.add_argument("--reconnect", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "install-rclone":
        return cmd_install_rclone()
    if args.command == "discard":
        return cmd_discard()
    if args.command == "authorize":
        return cmd_authorize(args)
    if args.command == "remove":
        return cmd_remove(args)
    if args.command == "reconnect":
        args.reconnect = True
    return cmd_setup(args)


if __name__ == "__main__":
    sys.exit(main())
