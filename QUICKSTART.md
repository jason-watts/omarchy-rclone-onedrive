# Quickstart

Walk the **jason-watts.rclone-onedrive** Omarchy bar plugin as if OneDrive had never been configured.

## 0. Confirm you are clean

```bash
rclone listremotes
findmnt -t fuse.rclone
systemctl --user list-units 'rclone*' --all
omarchy-shell jason-watts.rclone-onedrive status
```

You want no OneDrive remotes, no `~/onedrive/<name>` mount, and a status of **Needs setup**. If a remote is still there, use **Remove remote** in the panel.

## 1. Open the widget

Click the OneDrive cloud on the bar.

The panel should say **Set up rclone** / **First-time setup**, with **Personal** and **Work or school** rows. Clicking a row starts Microsoft sign-in.

If it still shows the old layout:

```bash
omarchy restart shell
omarchy-shell jason-watts.rclone-onedrive refresh
```

## 2. Sign in

1. Click **Personal Microsoft account** or **Work or school**.
2. A browser tab should open on `login.microsoftonline.com/consumers` (personal) or `/organizations` (work).
3. Finish Microsoft login. The panel closes while the browser is up, then opens again after Microsoft confirms.
4. The panel names the remote from the account domain (`omarchy@hey.com` → `hey-com`), creates `~/onedrive/<name>`, and switches to the status view.

Keys: `j`/`k` move, `Enter` starts sign-in on the highlighted account, `Esc` closes.

## 3. Check that it worked

```bash
rclone listremotes
findmnt ~/onedrive/<name>
systemctl --user is-active rclone-<name>.service
omarchy-shell jason-watts.rclone-onedrive status
```

In the panel:

- hero shows the remote name under **rclone OneDrive**
- the folder and terminal icons open the mount
- `p` or the toggle stops and starts the mount
- **Mount at boot** (or `b`) turns on `loginctl linger` so the user unit starts before login
- **Remove remote** unmounts, deletes the user unit, removes that rclone remote, and deletes the empty `~/onedrive/<name>` folder. Cloud files stay put.

## 4. What the wizard created

| Piece | Where |
|---|---|
| rclone remote | signed-in account domain (`omarchy@hey.com` → `hey-com`) in `~/.config/rclone/rclone.conf` |
| Mount | `~/onedrive/<name>` |
| systemd unit | `~/.config/systemd/user/rclone-<name>.service` |
| RC | `$XDG_RUNTIME_DIR/omarchy-rclone-onedrive.sock` (unix socket, no `--rc-no-auth`) |
