# Cloud Drives — Omarchy plugin

Mount **Google Drive**, **OneDrive**, **iCloud Drive** and **Proton Drive** as
folders under `~/Cloud/` from a bar widget. Built on [rclone](https://rclone.org).

```
~/Cloud/GoogleDrive
~/Cloud/OneDrive
~/Cloud/iCloudDrive
~/Cloud/ProtonDrive
```

## Install

```
omarchy plugin add https://github.com/edbron/omarchy-cloud-drives.git --enable
```

Dependencies (installed on first Connect via `omarchy pkg add`, sudo prompt):
`rclone`, `fuse3`. Also uses `secret-tool` (libsecret), `gum`, `jq` and `curl`, which ship with Omarchy.

## Usage

Click the cloud icon in the bar. Each drive has **Connect** (first time),
**Mount / Unmount**, **Open** and **Forget**. `j/k` move between drives,
`h/l` between actions, `Enter` activates.

Connect and Forget open a floating terminal for the interactive bits
(browser sign-in, 2FA, confirmation). Everything else is silent.

CLI: `~/.config/omarchy/plugins/edbron.cloud-drives/bin/omarchy-cloud-drives <state|setup|connect|disconnect|mount|unmount|open> [google|onedrive|icloud|proton]`

IPC: `omarchy-shell edbron.cloud-drives <state|refresh|toggle|mount ID|unmount ID|connect ID>`

## Security model

- **rclone's config is encrypted.** It holds OAuth refresh tokens and (for
  iCloud) the session/trust token. The encryption password is 256 random bits
  stored *only* in your login keyring (gnome-keyring, via `secret-tool`).
  rclone reads it through `RCLONE_PASSWORD_COMMAND`; it is never written to
  disk in the clear and never placed in an environment variable.
- **Google / OneDrive** authenticate with OAuth in your browser; the plugin
  never sees your password. Tokens can be revoked at any time from your
  Google / Microsoft account security pages.
- **iCloud** has no OAuth. rclone's `iclouddrive` backend needs your Apple ID
  password once (stored obscured inside the encrypted config) plus a 2FA
  code. The password is handed to rclone through its rc API over a private
  unix socket (request body built from stdin), so neither the clear nor the
  obscured value ever appears in a command line, the environment, logs or a
  temporary file. Prefer an app-specific password. Advanced Data Protection must be
  off for that Apple ID (Apple does not expose ADP-protected data to
  third-party clients). This backend is marked experimental by rclone.
- **Proton Drive** has no OAuth either. rclone's `protondrive` backend needs
  your Proton email and password, plus a 2FA code and/or the separate
  mailbox password if your account uses two-password mode. These go to
  rclone the same way as the iCloud password: over the private rc socket,
  never argv/env/logs/disk. Proton Drive's encryption keys must already
  exist — sign in once via a browser or the Proton Drive app before
  connecting here. Metadata caching (`enable_caching`) is forced off because
  rclone's own docs warn it doesn't see changes made by other clients, which
  would go stale under a VFS mount. This backend is marked experimental
  (Tier 4) by rclone.
- **Mounts** are user-private (`umask 077`, no `allow_other`) and run as
  systemd user units (`omarchy-cloud-drive@<Remote>.service`) bound to the
  graphical session so they stop with it. The units deliberately carry no
  systemd sandboxing: mount-namespace options would hide the FUSE mount from
  your session, and seccomp/`NoNewPrivileges` options break the setuid
  `fusermount3`. Unprivileged FUSE is the isolation boundary.
- Google: rclone's shared client_id is being retired during 2026. To keep
  working long-term, create your own OAuth client
  (https://rclone.org/drive/#making-your-own-client-id) and run
  `rclone config update GoogleDrive client_id=… client_secret=…`.
- Mount root `~/Cloud` is `0700`; the VFS cache lives in `~/.cache/rclone`
  (max 4 GB, 72 h) — remember it holds plaintext copies of recently used files.
- `~/.config/environment.d/60-omarchy-cloud-drives.conf` exports the same
  `RCLONE_PASSWORD_COMMAND` so plain `rclone` in your terminal keeps working.

## Files it touches

| Path | Purpose |
|------|---------|
| `~/.config/rclone/rclone.conf` | encrypted rclone config (0600) |
| `~/.config/systemd/user/omarchy-cloud-drive@.service` | mount unit template |
| `~/.config/environment.d/60-omarchy-cloud-drives.conf` | password-command for your shell |
| `~/Cloud/<Remote>` | mount points |
| keyring item `service=omarchy-cloud-drives key=config-password` | config key |

## Removing

Forget each drive from the panel, then:
```
systemctl --user disable --now 'omarchy-cloud-drive@*'
rm ~/.config/systemd/user/omarchy-cloud-drive@.service ~/.config/environment.d/60-omarchy-cloud-drives.conf
secret-tool clear service omarchy-cloud-drives key config-password
```
