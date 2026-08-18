# rclone OneDrive

Omarchy bar widget for an **rclone** OneDrive mount. It shows whether the mount is up, cloud quota, in-flight transfers, and start/stop.

This is not [OmaOneDrive](https://github.com/salemsayed/omaonedrive). That plugin talks to the abraunegg `onedrive` CLI. This one is for people who mount OneDrive with `rclone mount`.

## What it does

- Bar icon: official OneDrive cloud mark, themed to the shell. Bright when the mount is healthy, dim when stopped, urgent when failed, stale, or needs reauth.
- Panel: state, uptime, restarts, quota, cache, mount path, in-flight transfers, recent VFS-cache files.
- Open the mount in Files (Nautilus) or a terminal already `cd`'d there.
- Start / stop / restart the systemd unit. User units use `systemctl --user`. System units go through `pkexec`.
- Desktop notification when the mount drops or comes back (not for a user-initiated stop).

The helper never walks the live FUSE mount. Recent files come from `~/.cache/rclone/vfs/<remote>` only. Quota (`rclone about`) runs when you open the panel and on a slow timer, not on every bar poll.

## Requirements

- Omarchy Quattro (`omarchy-shell` plugins)
- Python 3
- `rclone` with an OneDrive remote
- A systemd unit that runs `rclone mount` (system or user)
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
- `Enter` activate
- `o` open in Files
- `t` open in Terminal
- `p` start / stop the mount
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
