# rclone OneDrive

Omarchy bar widget for an **rclone** OneDrive mount. It shows whether the mount is up, cloud quota, in-flight transfers, and start/stop.

This is not [OmaOneDrive](https://github.com/salemsayed/omaonedrive). That plugin talks to the abraunegg `onedrive` CLI. This one is for people who mount OneDrive with `rclone mount`.

**Walk through first-time setup:** [QUICKSTART.md](QUICKSTART.md).

## What it does

- Bar icon: 2025 OneDrive S-wave cloud, themed to the shell. Bright when the mount is healthy, dim when stopped, urgent when failed, stale, or needs reauth.
- Panel: state, uptime, restarts, quota, cache, mount path, in-flight transfers, recent VFS-cache files.
- Open the mount from the hero toolbar: Files (Nautilus) or a terminal already `cd`'d there.
- Start / stop / restart the systemd unit. User units use `systemctl --user`. System units go through `pkexec`.
- Desktop notification when the mount drops or comes back (not for a user-initiated stop).
- First-time setup: pick Personal / Work or school / SharePoint, name the rclone remote, then sign in at the matching Microsoft endpoint (`/consumers` vs `/organizations`). The plugin creates that remote and starts a user systemd mount.

The helper never walks the live FUSE mount. Recent files come from `~/.cache/rclone/vfs/<remote>` only. Quota (`rclone about`) runs when you open the panel and on a slow timer, not on every bar poll.

## First-time setup

If rclone or an OneDrive remote is missing, the panel is a wizard instead of the status view.

1. Choose **Personal Microsoft account**, **Work or school**, or **SharePoint library**.
2. Click **Sign in with Microsoft** (or press `L`).
3. Finish login in the browser. Personal uses `login.microsoftonline.com/consumers` so you do not land on a work tenant by mistake. Work uses `/organizations`.
4. The plugin writes `~/.config/systemd/user/rclone-<name>.service`, enables it, and mounts `~/OneDrive`.

`omarchy-shell jason.rclone-onedrive setup` starts the same flow. If the token later expires, the panel offers **Sign in again**.

## Requirements

- Omarchy Quattro (`omarchy-shell` plugins)
- Python 3
- `rclone` (the panel can launch `omarchy pkg add rclone` if it is missing)
- Optional: an existing systemd unit. New setups create a user unit automatically.
- Optional: rclone RC on `127.0.0.1:5572` for live transfer stats

## Install

```bash
omarchy plugin add https://github.com/jason-watts/omarchy-rclone-onedrive.git --enable
omarchy bar move jason.rclone-onedrive --section right
```

## rclone mount

A typical system unit:

```ini
[Unit]
Description=rclone OneDrive mount
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=YOURUSER
ExecStart=/usr/bin/rclone mount REMOTE: /path/to/mount \
  --vfs-cache-mode full \
  --log-level INFO \
  --rc --rc-addr 127.0.0.1:5572 --rc-no-auth
ExecStop=/bin/fusermount3 -u /path/to/mount
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

See `examples/rclone-rc.conf` for adding RC to an existing unit without editing it in place.

## Configure

Leave the remote, mount, and unit blank to auto-detect the first OneDrive rclone remote, its `fuse.rclone` mount, and a matching `*rclone*` systemd unit.

```bash
omarchy bar set jason.rclone-onedrive remote mydrive --json
omarchy bar set jason.rclone-onedrive mountPath /home/you/OneDrive --json
omarchy bar set jason.rclone-onedrive unit rclone-onedrive.service --json
omarchy bar set jason.rclone-onedrive rcUrl http://127.0.0.1:5572 --json
```

## Keys

- `j` / `k` move
- `h` / `l` move across the hero actions
- `Enter` activate
- `o` open in Files
- `t` open in Terminal
- `p` start / stop the mount
- `b` mount at boot (user linger)
- `r` refresh
- `Esc` close

Middle-click the icon opens Files. Right-click refreshes.

## IPC

```bash
omarchy-shell jason.rclone-onedrive status
omarchy-shell jason.rclone-onedrive refresh
omarchy-shell jason.rclone-onedrive files
omarchy-shell jason.rclone-onedrive terminal
```

## Safety

- No walk of the FUSE tree (that would pull OneDrive through `--vfs-cache-mode full`).
- No OAuth UI. Reauth is `rclone config reconnect REMOTE:` in a terminal.
- Pause/resume only starts or stops the discovered systemd unit.

## License

MIT
