# rclone OneDrive

Automate your OneDrive rclone configuration from the Omarchy bar. Sign in with Microsoft, mount the drive at `~/onedrive/<name>`, and open it in Files or a terminal.

## 1. Install

```bash
omarchy plugin add https://github.com/jason-watts/omarchy-rclone-onedrive.git --enable
omarchy bar move jason.rclone-onedrive --section right
```

Click the cloud icon on the bar.

## 2. Authenticate

Click **Personal Microsoft account** or **Work or school**. Finish sign-in in the browser. The panel comes back, names the remote from the account domain (`omarchy@hey.com` → `hey-com`), and mounts it at `~/onedrive/<name>`.

## 3. Open in Files or Terminal

Use the folder and terminal icons in the panel header. Middle-click the bar icon for Files. `o` opens Files, `t` opens a terminal in the mount.

## 4. Remove

**Remove remote** at the bottom of the panel unmounts, deletes the rclone login, and removes the empty `~/onedrive/<name>` folder. Cloud files stay in OneDrive.

```bash
omarchy plugin remove jason.rclone-onedrive
```

That only removes the plugin. Use **Remove remote** first if you also want the mount gone.

MIT. Needs Omarchy Quattro, Python 3, and `rclone`.
