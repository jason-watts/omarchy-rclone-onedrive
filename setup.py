#!/usr/bin/python3
"""First-run OneDrive setup for jason.rclone-onedrive.

Walks rclone's non-interactive config protocol, signs in at the matching
Microsoft endpoint (consumers vs organizations), names the remote from the
account domain, and writes a user systemd mount unit. Never prints tokens.
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
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

RCLONE_BIN = "/home/jason/.local/bin/rclone"
URL_RE = re.compile(r"https?://[^\s\"'<>]+")
TOKEN_RE = re.compile(r"\{[^{}]*\"access_token\"[^{}]*\}", re.S)
ACCESS_SCOPES = (
    "Files.Read Files.ReadWrite Files.Read.All Files.ReadWrite.All "
    "Sites.Read.All offline_access openid email profile User.Read"
)
JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*")

LOGIN_HOST = {
    "global": "login.microsoftonline.com",
    "us": "login.microsoftonline.us",
    "cn": "login.partner.microsoftonline.cn",
    "de": "login.microsoftonline.com",
}


def emit_line(payload: dict) -> None:
    json.dump(payload, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    sys.stdout.flush()


def emit(payload: dict) -> int:
    emit_line(payload)
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
    env["RCLONE_ONEDRIVE_ACCESS_SCOPES"] = ACCESS_SCOPES
    proc = subprocess.Popen(
        [bin_path, "authorize", "onedrive", "--onedrive-access-scopes", ACCESS_SCOPES],
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
        blob = extract_token_blob(stdout or "")
        if blob:
            return blob, ""
        return "", tail or "rclone authorize did not return a token"
    finally:
        cleanup()


def extract_token_blob(text: str) -> str:
    match = TOKEN_RE.search(text or "")
    if match:
        return match.group(0)
    start = (text or "").find("{")
    end = (text or "").rfind("}")
    if start >= 0 and end > start and "access_token" in text[start : end + 1]:
        candidate = text[start : end + 1]
        try:
            data = json.loads(candidate)
        except json.JSONDecodeError:
            return ""
        if isinstance(data, dict) and data.get("access_token"):
            return candidate
    return ""


def jwt_claims(token: str) -> dict:
    parts = str(token or "").split(".")
    if len(parts) < 2:
        return {}
    payload = parts[1] + "=" * (-len(parts[1]) % 4)
    try:
        data = json.loads(base64.urlsafe_b64decode(payload))
    except (ValueError, json.JSONDecodeError, OSError):
        return {}
    return data if isinstance(data, dict) else {}


def normalize_email(value: str) -> str:
    text = (value or "").strip()
    if "#" in text and "@" in text.split("#")[-1]:
        text = text.split("#")[-1].strip()
    if text.startswith("smtp:") and "@" in text:
        text = text[5:]
    if "@" not in text or " " in text:
        return ""
    return text


def email_from_value(value: object) -> str:
    if isinstance(value, str):
        return normalize_email(value)
    if isinstance(value, list):
        for item in value:
            found = email_from_value(item)
            if found:
                return found
        return ""
    if isinstance(value, dict):
        for key in (
            "preferred_username",
            "upn",
            "unique_name",
            "email",
            "mail",
            "userPrincipalName",
            "user_principal_name",
        ):
            found = email_from_value(value.get(key))
            if found:
                return found
        for key in ("emails", "otherMails", "proxyAddresses", "verified_primary_email"):
            found = email_from_value(value.get(key))
            if found:
                return found
        owner = value.get("owner")
        if isinstance(owner, dict):
            found = email_from_value(owner.get("user") or owner)
            if found:
                return found
    return ""


def email_from_jwts(text: str) -> str:
    for match in JWT_RE.findall(text or ""):
        found = email_from_value(jwt_claims(match))
        if found:
            return found
    return ""


def graph_json(access: str, url: str) -> dict:
    req = Request(
        url,
        headers={
            "Authorization": f"Bearer {access}",
            "Accept": "application/json",
        },
    )
    try:
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (HTTPError, URLError, TimeoutError, OSError, json.JSONDecodeError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def email_from_token_blob(token_blob: str) -> str:
    found = email_from_jwts(token_blob)
    if found:
        return found
    try:
        data = json.loads(token_blob)
    except json.JSONDecodeError:
        return ""
    if not isinstance(data, dict):
        return ""
    found = email_from_value(data)
    if found:
        return found
    for key in ("id_token", "access_token"):
        found = email_from_value(jwt_claims(str(data.get(key) or "")))
        if found:
            return found
    access = str(data.get("access_token") or "")
    if not access:
        return ""
    for url in (
        "https://graph.microsoft.com/v1.0/me?$select=userPrincipalName,mail,otherMails,proxyAddresses",
        "https://graph.microsoft.com/oidc/userinfo",
        "https://graph.microsoft.com/v1.0/me/drive?$select=owner,webUrl",
    ):
        found = email_from_value(graph_json(access, url))
        if found:
            return found
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
    if name == "access_scopes":
        return ACCESS_SCOPES
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
        "access_scopes",
        ACCESS_SCOPES,
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


def finish_mount(binary: str, remote: str, account: str, region: str, token: str, mount: str, rc: str) -> int:
    error = create_remote(binary, remote, account, region, token)
    if error:
        return fail(error)
    unit, _path = write_user_unit(remote, mount, rc)
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


def cmd_setup(args: argparse.Namespace) -> int:
    binary = rclone_bin()
    if not binary:
        return fail("rclone is not installed")
    clear_pending()
    account = args.account
    region = args.region or "global"
    remotes = existing_remotes(binary)
    mount = str(Path(args.mount or (Path.home() / "OneDrive")).expanduser())
    Path(mount).mkdir(parents=True, exist_ok=True)
    ends = endpoints(account, region)
    token, error = authorize(binary, ends["auth_url"], ends["token_url"])
    if error:
        return fail(error)
    emit_line({"ok": True, "action": "setup", "phase": "authorized"})
    if args.reconnect:
        remote = sanitize_remote(args.remote or "")
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
    remote = remote_from_email(email_from_token_blob(token), remotes)
    if not remote:
        return fail("Microsoft did not return an email for this account")
    emit_line({"ok": True, "action": "setup", "phase": "mounting", "remote": remote})
    return finish_mount(binary, remote, account, region, token, mount, args.rc)


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
        choices=["setup", "reconnect", "install-rclone", "remove"],
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
    if args.command == "remove":
        return cmd_remove(args)
    if args.command == "reconnect":
        args.reconnect = True
    return cmd_setup(args)


if __name__ == "__main__":
    sys.exit(main())
