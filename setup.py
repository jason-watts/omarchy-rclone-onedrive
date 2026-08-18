#!/usr/bin/python3
"""First-run OneDrive setup for jason.rclone-onedrive.

Walks rclone's non-interactive config protocol, signs in at the matching
Microsoft endpoint (consumers vs organizations), then writes a user systemd
mount unit. Never prints tokens.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

RCLONE_BIN = "/home/jason/.local/bin/rclone"
URL_RE = re.compile(r"https?://\S+")
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


def authorize(bin_path: str, auth_url: str, token_url: str) -> tuple[str, str]:
    env = os.environ.copy()
    env["RCLONE_ONEDRIVE_AUTH_URL"] = auth_url
    env["RCLONE_ONEDRIVE_TOKEN_URL"] = token_url
    proc = subprocess.Popen(
        [bin_path, "authorize", "onedrive", "--auth-no-open-browser"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=env,
    )
    opened = {"url": ""}

    def pump_err() -> None:
        assert proc.stderr is not None
        for line in proc.stderr:
            match = URL_RE.search(line)
            if match and not opened["url"]:
                opened["url"] = match.group(0).rstrip(").,")
                open_url(opened["url"])

    thread = threading.Thread(target=pump_err, daemon=True)
    thread.start()
    try:
        stdout, _stderr = proc.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        return "", "Microsoft sign-in timed out"
    thread.join(timeout=1)
    if proc.returncode != 0:
        return "", "Microsoft sign-in was cancelled or failed"
    blob = stdout or ""
    match = TOKEN_RE.search(blob)
    if match:
        return match.group(0), ""
    # rclone sometimes prints the JSON alone
    text = blob.strip()
    if text.startswith("{") and "access_token" in text:
        return text, ""
    return "", "rclone authorize did not return a token"


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
Restart=on-failure

[Install]
WantedBy=default.target
"""
    unit_path.write_text(body, encoding="utf-8")
    return unit, str(unit_path)


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


def cmd_setup(args: argparse.Namespace) -> int:
    binary = rclone_bin()
    if not binary:
        return fail("rclone is not installed")
    account = args.account
    region = args.region or "global"
    remote = re.sub(r"[^A-Za-z0-9_-]+", "", args.remote or "onedrive") or "onedrive"
    mount = str(Path(args.mount or (Path.home() / "OneDrive")).expanduser())
    if remote in existing_remotes(binary) and not args.reconnect:
        return fail(f"rclone remote {remote} already exists")
    Path(mount).mkdir(parents=True, exist_ok=True)
    ends = endpoints(account, region)
    token, error = authorize(binary, ends["auth_url"], ends["token_url"])
    if error:
        return fail(error)
    if args.reconnect and remote in existing_remotes(binary):
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
        return emit({"ok": True, "action": "reconnect", "remote": remote, "error": ""})
    error = create_remote(binary, remote, account, region, token)
    if error:
        return fail(error)
    unit, _path = write_user_unit(remote, mount, args.rc)
    error = enable_user_unit(unit)
    if error:
        return fail(error, remote=remote, mount=mount, unit=unit)
    # Give the notify mount a moment to appear
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
        choices=["setup", "reconnect", "install-rclone"],
    )
    parser.add_argument("--account", default="personal", choices=["personal", "business", "sharepoint"])
    parser.add_argument("--region", default="global")
    parser.add_argument("--remote", default="onedrive")
    parser.add_argument("--mount", default="")
    parser.add_argument("--rc", default="http://127.0.0.1:5572")
    parser.add_argument("--reconnect", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.command == "install-rclone":
        return cmd_install_rclone()
    if args.command == "reconnect":
        args.reconnect = True
    return cmd_setup(args)


if __name__ == "__main__":
    sys.exit(main())
