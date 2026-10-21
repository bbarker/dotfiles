# dotfiles

Portable encrypted workspace setup and commands: [Workspace drive](docs/WorkspaceDrive.md).
Check SSD devices and bind mounts: `nu scripts/check_binds.nu` (read-only; no sudo).

## Portable workspace SSD

Run these commands on the host from `/var/workspace/dotfiles`. The SSD provides `/var/workspace/AlygnApp` and `/var/workspace/shoggothox`; mounting and unmounting automatically back up committed Git history to their independent `-Host` clones. Use an extra backup during long sessions if desired; uncommitted files and build artifacts are not included in those Git backups. Before unmounting, finish builds and close project sessions, then disconnect only after the command succeeds. Mounting may prompt for the drive passphrase or sudo authorization. See the [workspace drive guide](docs/WorkspaceDrive.md) for setup and recovery.

```nu
nu scripts/check_binds.nu                         # Show SSD devices, mountpoints and project status
nu scripts/workspace-drive.nu mount              # Unlock, mount both projects and back up Git
nu scripts/workspace-drive.nu backup             # Optional extra Git backup
nu scripts/workspace-drive.nu unmount --quiescent # Back up, unmount and lock before disconnecting
```
