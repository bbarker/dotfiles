# Portable workspace drive

Tracking: <https://github.com/AlygnHealth/AlygnApp/issues/293>.

LUKS2 + XFS are formatted. The public UUIDs live in `workspace-drive.toml`.
Run these tools **on the host**, outside agent/container mount namespaces.
No command formats a disk, migrates files, renames a checkout or changes file
ownership recursively. Both existing checkouts remain on the internal disk.

The first pilot, `/var/workspace/shoggothox`, is on the SSD. The second migration
is `/var/workspace/AlygnApp`, renamed from AlygnResearch by the owner on 2026-10-21.
Both projects are enabled in the manifest and mounted from the SSD; AlygnApp's
cutover and host backup were verified on 2026-10-21. Disabled projects are excluded from mount, backup and unmount
operations. Existing AlygnResearch host backups are retained untouched. An
omitted `enabled` flag means true for compatibility with older manifests; no enabled
projects means lifecycle changes are refused. Re-enable Alygn only for a later,
separately planned migration window.

## Current implementation boundary

- The ordinary-clone backup engine has disposable-repository coverage for branches, tags,
  retagging, deleted branches, detached HEAD, inherited pruning settings, rejection
  of borrowed-object backups, unchanged work-in-progress, and restoration after
  deleting the source repository.
- Host identity resolution and refusal to overlay the existing nonempty checkout
  are checked. The supplied canonical IDs match this host's bbarker, borg and
  workspace group. The pilot is about 64 GiB (Git data about 114 MiB); the numeric
  owner/group scan found only `1000:1000`, `1000:30002`, `30033:30002`. Full per-file
  ACL/container mapping checks remain open. Shoggothox currently has uncommitted
  and untracked work: the eventual file migration must preserve it, even though
  the ordinary Git backup intentionally does not include it.
- Actual unlock/mount/unmount and busy-device recovery need a host smoke test.
  There is no agent-held passphrase or password. These are not yet verified live.
- Cross-host ID mapping is deliberately **not enabled**. If IDs differ, the mount
  command stops before unlocking/changing anything. Phase 3 requires a disposable
  ID-mapped-mount test (including chmod/new ownership and agent containers), full
  owner/ACL inventory, and an explicit host mapping. No automatic chown fallback.
- Active-project migration, absent-drive protection and second-host verification
  remain open. Do not substitute these scripts for the migration window.

## One-time host lock setup

Lifecycle operations serialize across host users with a shared lock. Create this
only if it does not already exist; **never replace a live lock file**:

```nu
if not ('/var/workspace/.workspace-drive.lock' | path exists) {
    sudo install -o bbarker -g workspace -m 0660 /dev/null /var/workspace/.workspace-drive.lock
}
```

Users running lifecycle commands need membership/access to that lock. If the
configured users/groups are absent, `owners` explains which lookup failed. Read
commands do not require the lock. Each host keeps its own lock on its internal disk.

## Inspect and prepare

From the dotfiles checkout:

```nu
nu scripts/check_binds.nu
nu scripts/workspace-drive.nu status
nu scripts/workspace-drive.nu owners
nu scripts/workspace-drive.nu prepare
```

`prepare` uses UDisks to unlock (interactive passphrase) and mount the filesystem,
checks its UUID/type and LUKS backing, and prints its actual desktop mount path.
It does not expose or modify a project. Leave the raw volume mounted for inventory
and migration planning. Do not put passphrases in command arguments or the manifest.
If authorization/any step fails, inspect `status`; a partial operation may leave the
drive unlocked or mounted. No automatic force cleanup is attempted.

The pilot will be `<volume>/projects/shoggothox`, bind-mounted at
`/var/workspace/shoggothox`. The script discovers `<volume>` from its UUID;
the desktop's `/media/...` location is not the canonical project path.

## Migration window (not performed)

1. Inventory all owners/groups/ACLs, worktrees, space and mount namespace mappings.
   Include hidden files and build output; don't read or print credential contents.
2. Prepare a permission-preserving initial rsync copy and verify it. Copying the
   checked-out data is separate from the committed-history backup. Do not use
   `--delete`, change ownership en masse, or remove the original automatically.
3. Stop writers for the final copy/verification and directory switch. Keep the old
   checkout at an explicitly agreed rollback path on the internal disk. This path
   is separate from the ordinary `<project>-Host` backup clone.
4. Leave an empty root-owned, non-writable mountpoint at the canonical project
   path. That is the absent-drive guard; do not make a new writable checkout there.
   A privileged process can bypass this guard; document that limit.
5. Verify worktree `.git`/common-dir paths and restart existing containers where
   required. Never switch mounts while a running build/agent still uses old paths.
6. Mount the migrated project with the command below, verify a host backup and
   representative build, then validate safe removal and a second host. Original
   host-copy deletion requires a separate, explicit cleanup decision.

## Everyday lifecycle (after migration and live verification)

```nu
nu scripts/workspace-drive.nu mount
# Finish editors, builds and agent work first:
nu scripts/workspace-drive.nu unmount --quiescent
# Optional extra capture during a long session:
nu scripts/workspace-drive.nu backup
```

`mount` refuses nonempty destinations/unrelated mounts, checks canonical IDs,
unlocks/mounts as needed and runs a backup. A backup failure is an operation failure
even if project mounts succeeded. Do not pull the cable after an error.

`backup` requires the expected SSD-backed project mounts. `unmount --quiescent`
confirms the operator has stopped writers; it cannot stop unrelated processes
committing. It backs up the raw projects, unmounts project views, flushes writes,
unmounts the filesystem and locks LUKS. Busy unmounts fail normally; there is no
forced/lazy detach or implicit backup bypass while the drive is attached. It can retry
after partial project unmounts and is safe to repeat: with nothing mounted it only locks
a drive left unlocked, or says there is nothing to do.

### After the drive was pulled while mounted

If the cable was pulled (or the drive reset) with the project views still bound, the
bind mounts outlive the disk: their LUKS mapping `luks-<LUKS UUID>` has no disk under it,
`findmnt` shows no filesystem UUID for them, and `mount` refuses with "not the configured
SSD project mount". `unmount --quiescent` recognises exactly this state - every
mount of the configured mapping with no readable filesystem, and a mapping whose
sysfs disk links no longer resolve - and then:

1. says no final backup is possible this run and prints when each host backup was last
   updated (the SSD still holds anything newer; replug and `backup` to capture it);
2. lazily detaches those mounts (there is nothing readable left for a lazy detach to lose);
3. closes the dead mapping (`cryptsetup close`, then `dmsetup remove --force`);
4. if processes still hold the dead drive it lists them and has the kernel remove the
   mapping when the last of them lets go (`dmsetup remove --deferred`). It finds them
   however they hold it, not only by `lsof`: a working directory or open file that now
   fails with an I/O error, a watch on its files, a mapped file, or a mount namespace of
   their own that still has it mounted. Each row says which, so an editor's language
   server is not a mystery. A process of another user is invisible to an ordinary user:
   run `sudo nu scripts/workspace-drive.nu unmount --quiescent` to see them all.
   Restart those processes; `mount` refuses while the dead mapping remains. Repeating the
   command is safe.

`unmount --quiescent --force` goes one step further for a mapping that a process still
holds: it renames the dead mapping (`dmsetup rename`, allowed while a device is open) so its
name is free for the replugged drive to be unlocked under, and leaves the dead device to
disappear when the last holder exits. It changes nothing unless a drive was pulled while
mounted, and it cannot make the holder let go. The kernel may still refuse to mount the
replugged filesystem while the old one lingers (the same filesystem UUID twice); in that
case end the processes in the table, or reboot. It worked on the first real dead
mapping (it renamed it to `luks-<UUID>-dead-<time>`); each later run lists what still
holds the renamed device until it disappears.

A mapping whose disk is still attached is never treated this way, and none of it runs
against a live mount. Afterwards `mount` unlocks the replugged drive as usual.

## Host Git history and restoration

`/var/workspace/shoggothox-Host` is the pilot's ordinary independent clone on the internal
filesystem, created with `git clone --no-local`. It has checked-out files and its own
objects: no object alternates, linked worktree or local-clone hardlinks to the SSD.

Backups happen automatically after mounting and before unmounting; manual `backup`
is optional for long sessions. Each backup fetches source branches into `origin/*`
and updates tags, with pruning explicitly disabled even if inherited Git settings
enable it. A moved source tag replaces the backup tag. There are no timestamped
generations or archival namespaces. Rewritten history can eventually disappear if
no remaining ref retains it; that tradeoff is intentional.

Only Git refs/objects are updated during routine backup. The host clone's local
branches, checked-out files and working changes are left alone; browsing files may
therefore show an older commit. Inspect `origin/main` for the latest backed-up main
branch (use `origin/music-sources` for the pilot's currently active branch).
`origin/HEAD` is a direct ref to the source's latest committed HEAD, including
a detached HEAD, rather than the default clone's symbolic default-branch alias.
It does not change the host clone's own HEAD.

Concurrent source-ref changes cause failure; finish writers and retry. Detached
HEADs in additional linked worktrees and separate submodule/LFS stores still need
inventory and any necessary extension. Current capture covers source HEAD, branches
and tags. To restore the latest source HEAD without modifying the backup clone:

```nu
git clone --no-local /var/workspace/shoggothox-Host /var/workspace/shoggothox-Restore
git -C /var/workspace/shoggothox-Restore fetch /var/workspace/shoggothox-Host refs/remotes/origin/HEAD
git -C /var/workspace/shoggothox-Restore checkout -b recovered FETCH_HEAD
```

Source history need not be pushed to GitHub. No working changes, untracked/ignored files, secrets outside committed
history or build cache are backed up. A mid-session drive failure can lose commits
since the last successful capture; use the explicit backup command in long sessions.
The host copy contains private Git history and should stay on encrypted host storage.

The previously created ordinary `/var/workspace/AlygnResearch-Host` remains in place
but is excluded from pilot lifecycle operations. Its original bare backup was retained intact at
`/var/workspace/AlygnResearch-Host-LegacyBare` when the verified ordinary clone was
installed. It is a one-time rollback copy, not part of the routine backup workflow;
no further generations are written there. Cleanup can be decided separately.

## Verification

```nu
nu scripts/test-workspace-drive.nu
nu scripts/test-workspace-pilot.nu
nu scripts/workspace-drive.nu --help
```

The test creates disposable Git repositories in the host temporary directory, makes
synthetic commits and removes those temporary repositories. It never opens the SSD.
No Alygn Rust/wasm rebuild is needed for these dotfiles-only changes.

## Initial-copy handoff — 2026-10-18

The host now reports the configured LUKS and XFS UUIDs unlocked and mounted at
`/media/bbarker/workspace`. Its parent ACL permits only bbarker to traverse;
the agent cannot access the filesystem and has no passwordless sudo. Source
inventory currently measures about 3 GiB (Git about 114 MiB), with owners
`1000:1000`, `1000:30002`, `30033:30002`. One Git worktree remains on
`music-sources`. The source scan found no .gitmodules/.gitattributes files or
Git LFS directory; no gitlink index entries or local LFS filter settings were
reported. Recursive ACL metadata was inspected without opening file contents;
the named ACL entries found were for workspace group 30002. Container mapping
verification remains open.

`scripts/workspace-pilot-copy.nu --copy` is a **root-only initial-copy helper**.
Run it with sudo and an absolute path to the host's Nu executable. It serializes
with the lifecycle lock, validates filesystem/encryption UUIDs, checks free space,
reports XFS features and refuses nested source mounts or an existing destination.
It adds only a nonrecursive workspace-group traversal ACL to the desktop mount's
parent and filesystem root, creates the projects directory if missing, and uses
`rsync -aHAX --numeric-ids --one-file-system` without deletion. Existing project
ownership/ACLs are preserved. No active checkout is renamed or overlaid, and no
process is stopped. Parsing/help and the unprivileged refusal were checked; the
privileged copy has **not** run. A failed partial copy requires inspection before
retrying; the helper deliberately refuses an existing destination.

Shell and Codex processes currently have the source as their working directory;
Zed is running, but its open-file references cannot be fully inspected as borg.
All may remain active for this preliminary copy. Before final synchronization and
cutover, pause writers and release old directory/file references. Do not kill Zed;
coordinate saving/reopening the project as needed. Live copying is not a consistent
snapshot: files removed or changed meanwhile must be reconciled explicitly during
the final synchronization. Leave both copies in place until verification.

### Initial copy verified in part — 2026-10-18

Brandon ran the initial copy successfully: 18,571 entries, 3,149,377,446 bytes
logical size. Reported XFS metadata confirms 4 KiB blocks, CRCs and reflinks.
The original project remains on internal ext4; no cutover occurred. SSD Git
connectivity passes and both HEADs are `da0eb6962646c4983868d23a4c702e29d99bdf38`.
A size/symlink comparison reports no differences, but is not a content checksum.
Borg's disposable create/read/write/rename/chmod/delete probe passes on the SSD.

**Outstanding before cutover:** metadata dry-run reports access-ACL differences
on 16,808 regular-file entries. Directory ACLs remain present, but regular-file
named workspace-group entries are absent, including two source files with owning
group 1000. Matching mode bits alone are therefore insufficient verification.
The cause has not yet been established. The helper now supports `--restore-acls`,
which validates the same backing drive and existing destination, serializes with
the lifecycle lock, and reapplies source ownership/modes/ACLs via mapped `getfacl`
metadata and `setfacl --restore`. It does not change contents, delete files, switch
directories or stop processes. An ext4-to-XFS disposable ACL restoration test
passes; production restoration still requires Brandon's sudo invocation followed
by another metadata comparison. Future `--copy` runs include this restoration.
Zed and the source shell/Codex sessions remain untouched.

### ACL restoration verified — 2026-10-18

Fresh recursive numeric owner/group/mode/ACL inventories match across all 18,560
non-symlink entries after normalizing root paths and traversal order. Rsync's
metadata dry run reports only the project root directory timestamp, changed by
disposable access probes. Forward and reverse size/symlink comparisons report no
differences, including no extra destination entries. These are not full file-content
checksum comparisons. Copied Git connectivity passes; source and SSD HEAD remain
`da0eb6962646c4983868d23a4c702e29d99bdf38`.

No final sync or cutover has happened. Shell PID 3289465 and Codex PID 3310969
still have the host source as their working directory. Before final cutover, pause
writers, move those sessions out of the project, save Zed changes and release its
project references as needed; keep the editor process running. Retain the original
host tree separately from `shoggothox-Host`. Final synchronization must explicitly
reconcile removals and re-verify metadata before a mount switch.

## Final pilot switch (host sudo required)

User confirmed writers paused and project references released. No switch has yet
run. `scripts/workspace-pilot-switch.nu --switch-to-ssd` is the one-time privileged
handoff. Execute with sudo and the host Nu executable from outside both trees.
Keep Zed running but its shoggothox project closed until success is verified.

The --switch-to-ssd option names the action; keep writers paused before invoking it. The helper holds the shared lifecycle lock, checks fixed pilot selection, numeric
IDs, XFS/LUKS UUIDs and canonical paths, and uses root lsof to reject open references
to either copy (inspection warnings are also failures). It copies without deletion,
restores ACL metadata, checksum-verifies the forward copy, detects extra destination
entries through a reverse dry run, compares normalized ACL inventories and checks
Git connectivity. A failed comparison leaves the original path untouched.

After a second idle check, it renames the original to the fixed rollback path
`/var/workspace/shoggothox-PreSSD`, creates a root-owned 0555 mountpoint with inherited
ACLs removed, then bind-mounts the SSD pilot at the original canonical path. Mount
setup failures restore the original when no mount exists. A later verification or
backup failure may leave the SSD project mounted: inspect status rather than blindly
retrying (the retained rollback path deliberately prevents a second cutover).
Committed-history backup runs as borg through the existing lifecycle engine, with
the already-held lock. The original host copy is never deleted by this helper.

By default no process is stopped. Idle checks are point-in-time observations; keep writers
paused throughout. Existing containers may still need restarting to see the host
mount. A new empty mountpoint discourages ordinary tools from building into the
host directory while the SSD is absent; root or an intentional rename/replacement
by a user with write access to the parent can bypass it.

Validation completed: Nu parsing/help, quiescence/privilege refusal, and disposable
verification cases for same-size/same-time content corruption, extra files and a
matching copy. Privileged rename/mount/backup remains unexecuted until host handoff.


Verification diagnostics: the switch helper now accepts --verify-only to run the privileged content/metadata comparisons without syncing, renaming or mounting. Failed comparisons print rsync change codes and paths, never contents or hashes. The prior privileged comparison failed without details; a subsequent borg comparison found no differences, so the cause is still unconfirmed. Run privileged verification before another switch attempt.

### Root-only extended-attribute mismatch — 2026-10-18

The privileged verification reports `.f........x` whereas borg's comparison is
clean. Content checks do not report mismatches. This strongly matches XFS exposing
`trusted.SGI_ACL_FILE` / `trusted.SGI_ACL_DEFAULT` to CAP_SYS_ADMIN callers, alongside
the portable POSIX ACL view. The kernel implementation explicitly lists both views:
https://github.com/torvalds/linux/blob/master/fs/xfs/xfs_xattr.c . Root-side attribute
names on this SSD have not yet been independently captured, so treat this as the
supported diagnosis awaiting the next privileged verification, not a completed
root-cause reproduction. It also explains rsync removing effective ACLs during the
initial copy and seeing extras again after explicit ACL restoration.

Shared `scripts/workspace-rsync.nu` now excludes precisely those two internal names
from copy and checksum verification; it retains rsync's normal root-side `system.*`
exclusion explicitly because specifying xattr filters overrides implicit filtering.
All other xattrs remain copied and checked; `-A` and independent normalized getfacl
inventories continue to verify effective ACLs. No broad ignore-xattrs workaround.
Source files and the active path remain unchanged.

`nix shell nixpkgs#attr --command nu scripts/test-workspace-rsync.nu` passes with
disposable files: named POSIX ACL preservation, user-xattr preservation, deliberately
corrupted user-xattr detection and repair. Syntax checks pass for the shared module,
test and both consuming helpers. Root-only XFS handling remains to be verified on
the host. Keep writers paused; the updated switch command repeats verification
before any rename or mount. It still stops and prints differences if any remain.

## Pilot cutover and backup completed — 2026-10-18

- Final rsync sync, content-checksum verification, normalized ownership/mode/ACL
  comparison and Git connectivity passed after the narrow XFS-internal-ACL filters.
- `/var/workspace/shoggothox` is now an XFS bind mount with filesystem UUID
  `4ddbc129-272d-41ab-873e-1911e6670c0d`, filesystem root `/projects/shoggothox`.
- The full original host checkout, including working files, remains intact on
  internal ext4 at `/var/workspace/shoggothox-PreSSD`. It is the rollback copy,
  distinct from the committed-history backup. Do not work in it or delete it yet.
- The one-time helper stopped after mounting when its backup hit Git 2.43's
  foreign-owner check on the source `.git`. The agent reproduced the failure
  with Git's foreign-owner test hook under host Git 2.43; Git 2.50 did not reproduce
  it. Normal `-c` and environment-config propagation did not survive the older
  local upload-pack boundary. The fix passes exact source Git-directory trust
  directly on the local upload-pack command with shell-quoted arguments. No
  global safe.directory setting or wildcard was added. Clone and fetch both use it.
- `scripts/test-workspace-git-ownership.nu` failed before the fix on Git 2.43 and
  now passes on 2.43 and 2.50, including spaces/apostrophes, initial clone, repeat
  fetch and continued rejection by unrelated Git commands. Existing backup/restore
  regression tests also pass on both versions. Nu parsing and diff checks pass.
- The agent completed the **normal lifecycle backup command** as borg under host
  Git 2.43. Independent `/var/workspace/shoggothox-Host` now has latest source HEAD
  `da0eb6962646c4983868d23a4c702e29d99bdf38`; mount and matching backup ref verified.
- Zed was not stopped. AlygnResearch remains on its original filesystem and disabled
  in the pilot manifest. Dotfiles implementation changes remain uncommitted.

The pilot can now be reopened at `/var/workspace/shoggothox`; keep the SSD attached.
Do not rerun the one-time switch helper (its retained rollback-path guard prevents
that). Remaining verification includes representative builds, concurrent worktrees,
normal unmount/remount and busy/failure handling, container mount visibility and
second-host ownership/cache portability. Preserve both rollback and Git backup.


## Read-only bind and SSD overview

Run `nu scripts/check_binds.nu` on the host to show the configured SSD status
(disconnected, locked, unlocked or mounted), physical device/model/transport,
encrypted partition, unlocked filesystem device, every SSD mountpoint and each
project bind. Correct binds are matched by filesystem UUID, type and filesystem
root; unrelated mounts are labeled DIFFERENT MOUNT. Disabled projects remain
visible as deferred when not mounted. No sudo or mutation is needed.

`--json` returns structured output; `--config <path>` selects another manifest.
The normal manifest is resolved relative to the script, so invoking it by absolute
path works from any directory. Status describes the current mount namespace; an
existing container may see different mounts than the host. This is a mount-status
report, not a data-integrity or backup-freshness check. Live and temporary-manifest
checks cover mounted status, JSON, disconnected SSD and mismatched binds.

## AlygnApp migration prepared — 2026-10-21

Optional process cleanup is now available on the final switch command as `--kill`.
After saving work and closing the important sessions manually, invoke it from
outside both project trees:

```nu
cd /var/workspace/dotfiles
sudo (which nu | first | get path) scripts/workspace-pilot-switch.nu --project AlygnApp --switch-to-ssd --kill
```

It prints the remaining project-holder PIDs/names, sends TERM, waits up to five
seconds, then sends KILL to surviving original processes. This can close remaining
agents, terminals and adb; save work first. Cleanup is confined to processes with
references under the selected source or SSD project. Zed and its ancestors, and
the invoking helper's process chain, are protected. If any protected holder is
found, no processes are signalled; release its references manually. PID start times
are rechecked before signals. Replacement/restarting processes are not chased:
the final reference check stops the switch if any remain. No other project is
selected. The `--verify-only` action rejects `--kill`.

The scan inspects open references directly rather than recursively enumerating
over a million build files. Known unrelated desktop FUSE mounts are excluded;
other inspection warnings remain fatal. Root privileges are still required for a
complete host scan. Normal invocation without `--kill` continues to refuse open
references without signalling anything. After checksum verification, references
are checked again without further killing; keep services/writers paused.

`nu scripts/test-workspace-processes.nu` exercises only disposable sleepers under
temporary directories: TERM cleanup, TERM-resistant KILL escalation, unrelated
process survival, helper/ancestor protection and a synthetic Zed-named fixture.
The protected-process test also verifies that no other holder is partially stopped.
No cleanup has been run against the real project sessions by the agent.

The owner renamed `/var/workspace/AlygnResearch` to `/var/workspace/AlygnApp`.
Git reports one worktree, now at the new path on `main`; no remaining linked Git
worktrees were reported. Source is still internal ext4, about 248 GiB. The SSD is
mounted and has about 1.8 TiB free. Numeric owners remain within the configured
IDs: `1000:1000`, `1000:30002`, `30033:30002`, `30033:30033`.

Manifest now enables AlygnApp with SSD directory `projects/AlygnApp`, canonical
target `/var/workspace/AlygnApp`, and independent backup `/var/workspace/AlygnApp-Host`.
The agent created and verified that ordinary clone at committed HEAD
`b2f38bb4e5235c17abc31126d5232d5cbca49dea`. Existing AlygnResearch backups remain
untouched. Shoggothox remains mounted with its original manifest paths.

The existing copy/switch helpers accept `--project AlygnApp` (default remains
shoggothox for compatibility). Shared migration selection rejects disabled,
duplicate or mismatched canonical project definitions and selects only the named
project even when multiple are enabled. The final switch backs up only that project
using `workspace-drive.nu backup --project AlygnApp`; project selection on raw-drive
mount/unmount is deliberately refused. Ordinary backup still defaults to all enabled
projects; until AlygnApp is mounted, use `backup --project shoggothox` when needed.
Tests cover project selection/refusals, old selection behavior, syntax, privilege
guards and the Git 2.43 ownership case. No SSD copy or AlygnApp mount switch has run.

Run in a host Nushell, outside the source directory:

```nu
sudo (which nu | first | get path) /var/workspace/dotfiles/scripts/workspace-pilot-copy.nu --project AlygnApp --copy
```

The initial copy may run while references remain; it preserves metadata and all
working files and uses the verified XFS ACL-attribute filters. It needs host sudo
because mixed ownership and ACLs cannot be preserved by the agent account. Keep
the SSD attached. Before the final switch, release old references and pause writers:

```nu
sudo (which nu | first | get path) /var/workspace/dotfiles/scripts/workspace-pilot-switch.nu --project AlygnApp --switch-to-ssd
```

That command rechecks idleness, performs final sync/checksum/ACL verification, keeps
the full original at `/var/workspace/AlygnApp-PreSSD`, and bind-mounts only AlygnApp.
Without `--kill`, it stops without switching if references remain and signals no processes. Renaming
a directory does not release existing process references to its inode. Last observed
holders were borg Codex PIDs 1953523/1600733, helper 2594996, adb 2756449, tmux client
3186008 and Bash 3925825. No processes were stopped by this migration preparation.

### AlygnApp initial copy verified — 2026-10-21

Owner completed the sudo initial copy: 277,394,639,121 bytes logical size,
263,279,628,613 bytes sent. Source remains on internal ext4 at `/var/workspace/AlygnApp`;
destination is on the configured XFS SSD at `/media/bbarker/workspace/projects/AlygnApp`.
Fresh normalized numeric ownership/mode/ACL inventories match across 1,167,078
non-symlink entries. Copied Git connectivity passes; source and copied HEAD both
equal `b2f38bb4e5235c17abc31126d5232d5cbca49dea`. Full final content checksum verification
will run in the privileged switch helper after writers/references are released.

Six persistent borg processes still have the project as their cwd: Codex 1600733
and 1953523, codex-code-mode 2594996, adb 2756449, tmux client 3186008 and Bash
3925825. No process was stopped. No AlygnApp directory rename/bind switch has run;
the original remains active and there is no AlygnApp-PreSSD yet. Leave the SSD
attached, finish/release those sessions, then run the targeted switch command.

## AlygnApp SSD cutover completed — 2026-10-21

- Owner ran the targeted switch with opt-in process cleanup. Final content and
  metadata verification passed, and the helper reported CUTOVER COMPLETE.
- Agent independently confirmed `/var/workspace/AlygnApp` is a bind mount of
  `/projects/AlygnApp` on XFS UUID `4ddbc129-272d-41ab-873e-1911e6670c0d`.
- Full original checkout remains on internal ext4 at `/var/workspace/AlygnApp-PreSSD`.
  Do not work in that rollback copy or delete it until later verification/cleanup.
- Independent `/var/workspace/AlygnApp-Host` has latest source committed HEAD
  `b2f38bb4e5235c17abc31126d5232d5cbca49dea`, matching the active checkout. Normal
  lifecycle backup completed successfully during the switch.
- Shoggothox's existing SSD bind mount remains correct. Previous AlygnResearch
  backups remain in place. Both active projects are now covered by ordinary
  mount/unmount backup operations; no targeted backup workaround is needed.
- Reopen the application project at `/var/workspace/AlygnApp`. Existing agent
  containers may require restarting to observe the host's new mount. Keep the SSD
  attached while either project is used. Do not rerun the one-time switch helper.

The data migration milestone is complete. Remaining #293 work includes ordinary
unmount/remount and busy/failure verification, representative builds and concurrent
worktree/cache behavior, container access and second-host ownership/portability.
All original source copies and historical Git backups remain retained. Dotfiles
implementation changes are still uncommitted; no commit or cleanup was performed.
