# Quickstart — test setup from a clean slate

You are on a machine that already had a philotic rclone mount. This is the
path to walk the **plugin wizard** as if you had never configured OneDrive.

## 0. Confirm you are clean

```bash
rclone listremotes
systemctl --user is-active rclone-onedrive.service
findmnt ~/OneDrive
omarchy-shell jason.rclone-onedrive status
```

You want:

- no remotes
- user unit inactive / missing
- `~/OneDrive` not mounted
- status: `Needs setup`

If a remote or mount is still there, skip to [Reset and try again](#reset-and-try-again).

## 1. Open the widget

Click the **OneDrive cloud** on the bar (right side, by Tailscale).

The panel should say **Set up rclone** / **First-time setup**, with three
account rows and **Sign in with Microsoft**.

If it still shows Connected / Mount stopped:

```bash
omarchy restart shell
omarchy-shell jason.rclone-onedrive refresh
```

Then click the icon again.

## 2. Sign in

1. Click **Personal Microsoft account** (that is the old philotic account type).
   Clicking the row starts login. **Sign in with Microsoft** does the same.
2. A browser tab should open on
   `login.microsoftonline.com/consumers` (not `/common`, not a quoted
   `localhost:53682/"`).
3. Finish Microsoft login.
4. The panel says **Waiting for the browser…**, then switches to the
   status view.

Keys if you prefer the keyboard: `j`/`k` move, type a remote name, `Enter` or `L` starts sign-in, `Esc` closes.

## 3. Check that it worked

```bash
rclone listremotes          # expect the name you typed
findmnt ~/OneDrive          # expect that name as fuse.rclone
systemctl --user is-active "rclone-<name>.service"   # active
/bin/ls ~/OneDrive | head
omarchy-shell jason.rclone-onedrive status           # Connected
```

In the panel:

- hero is Connected, toggle is on
- Mount is `/home/jason/OneDrive`
- the folder and terminal icons in the hero open the mount
- `p` or the toggle stops and starts the mount
- At the bottom, **Mount at boot** (or `b`) turns on `loginctl linger` so the user unit starts before login

If a terminal was already `cd`’d into `~/OneDrive` before a remount:

```bash
cd ~
/bin/ls ~/OneDrive
```

A leftover FUSE handle prints `Transport endpoint is not connected`.

## 4. What the wizard created

| Piece | Where |
|---|---|
| rclone remote | the name you typed, in `~/.config/rclone/rclone.conf` |
| Mount | `~/OneDrive` |
| systemd unit | `~/.config/systemd/user/rclone-<name>.service` |
| RC | `http://127.0.0.1:5572` |

This is **not** the old system unit `rclone-philotic.service` or
`/black/onedrive/philotic`.

## Reset and try again

```bash
systemctl --user disable --now rclone-onedrive.service
fusermount3 -uz "$HOME/OneDrive" || true
rm -f "$HOME/.config/systemd/user/rclone-onedrive.service"
systemctl --user daemon-reload
rclone config delete onedrive
omarchy-shell jason.rclone-onedrive refresh
```

Then start again at step 1.

## Restore an older config

These copies were made before the last wipes. They are **not** used until
you copy one back.

```bash
# Wizard setup from 2026-08-18 (remote onedrive, ~/OneDrive)
cp -a ~/.config/rclone/rclone.conf.bak-onedrive-20260818-101847 ~/.config/rclone/rclone.conf

# Original philotic remote (does not recreate the deleted system unit)
cp -a ~/.config/rclone/rclone.conf.bak-philotic-20260818-095242 ~/.config/rclone/rclone.conf
```

After restoring philotic you still need a mount unit. The old
`rclone-philotic.service` was removed from `/etc/systemd/system/`.
