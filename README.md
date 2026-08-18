# rclone OneDrive

Omarchy bar widget for an **rclone** OneDrive mount. It shows whether the mount is up, cloud quota, in-flight transfers, and start/stop.

This is not [OmaOneDrive](https://github.com/salemsayed/omaonedrive) (abraunegg `onedrive` CLI) and not the multi-provider [rclone bar](https://github.com/davidszp/omarchy-rclone). This plugin is OneDrive-only: first-run Microsoft sign-in, a user systemd mount, and VFS-cache status.

## Install

```bash
omarchy plugin add https://github.com/jason-watts/omarchy-rclone-onedrive.git --enable
omarchy bar move jason.rclone-onedrive --section right
```

Then click the OneDrive icon on the bar.

## Remove

```bash
omarchy plugin remove jason.rclone-onedrive
```

That only removes the plugin. Your rclone remote, `~/onedrive/<name>` mount, and user unit stay until you use **Remove remote** in the panel.

## What it does

- Bar icon: 2025 OneDrive S-wave cloud, themed to the shell. Bright when the mount is healthy, dim when stopped, urgent when failed, stale, or needs reauth.
- Panel: state, uptime, restarts, quota, cache, mount path, in-flight transfers, recent VFS-cache files.
- Open the mount from the hero toolbar: Files or a terminal already `cd`'d there.
- Start / stop / restart the systemd unit. User units use `systemctl --user`. System units go through `pkexec`.
- Desktop notification when the mount drops or comes back (not for a user-initiated stop).
- First-time setup: click Personal or Work or school. The remote is named from the account domain (`you@example.com` → `example-com`) and mounted at `~/onedrive/<name>`.

The helper never walks the live FUSE mount. Recent files come from `~/.cache/rclone/vfs/<remote>` only. Quota (`rclone about`) runs when you open the panel and on a slow timer, not on every bar poll.

## First-time setup

If rclone or an OneDrive remote is missing, the panel is a wizard instead of the status view.

1. Click **Personal Microsoft account** or **Work or school**. That starts Microsoft sign-in.
2. Finish login in the browser. Personal uses `login.microsoftonline.com/consumers`. Work uses `/organizations`. The panel closes while the browser is up, then opens again after Microsoft confirms.
3. The remote is named from the signed-in domain (dots become hyphens). The plugin writes `~/.config/systemd/user/rclone-<name>.service`, enables it, and mounts `~/onedrive/<name>`.

If the token later expires, click Personal or Work or school again.

A longer walkthrough is in [QUICKSTART.md](QUICKSTART.md).

## Requirements

- Omarchy Quattro (`omarchy-shell` plugins)
- Python 3
- `rclone` (the panel can launch `omarchy pkg add rclone` if it is missing)
- `fusermount3` for unmount
- Optional: an existing systemd unit. New setups create a user unit automatically.
- Optional: rclone RC on `127.0.0.1:5572` for live transfer stats

## rclone mount

A typical system unit, if you already have one:

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
omarchy bar set jason.rclone-onedrive mountPath /home/you/onedrive/example-com --json
omarchy bar set jason.rclone-onedrive unit rclone-mydrive.service --json
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

**Remove remote** is at the bottom of the panel. It unmounts, deletes the user systemd unit, runs `rclone config delete`, and removes the empty `~/onedrive/<name>` folder. Cloud files stay in OneDrive.

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
- First-run and expired-token sign-in happen in the panel. The remote name is always the account domain.
- Pause/resume only starts or stops the discovered systemd unit.

## License

MIT
