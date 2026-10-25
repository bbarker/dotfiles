#!/usr/bin/env nu
# Host-only lifecycle. Never formats, copies or renames an active project.
use workspace-git.nu [checked backup-repository]

def load-config [file: path] {
    let config = (open $file)
    for value in [$config.drive.luks_uuid $config.drive.filesystem_uuid] {
        if not ($value =~ '^[0-9a-fA-F-]{36}$') { error make {msg: 'Invalid drive UUID in manifest.'} }
    }
    for project in $config.projects {
        if not ($project.name =~ '^[A-Za-z0-9_-]+$') { error make {msg: 'Invalid project name.'} }
        if not ($project.target | str starts-with '/var/workspace/') { error make {msg: 'Project target must be under /var/workspace.'} }
        if ($project.target | path expand) != $project.target { error make {msg: 'Project target must be a canonical absolute path.'} }
        if ($project.directory | path expand --no-symlink) == $project.directory or ($project.directory | split row '/' | any {|part| $part in ['..' '.'] }) {
            error make {msg: 'Project directory must be relative and cannot contain dot segments.'}
        }
        if ($project.backup | path expand) != $project.backup or $project.backup == $project.target {
            error make {msg: 'Backup must have a separate canonical absolute path.'}
        }
    }
    # Keep deferred project definitions without selecting them for any operation.
    $config | upsert projects ($config.projects | where {|project| $project.enabled? | default true })
}

def device [uuid: string] { $'/dev/disk/by-uuid/($uuid)' }

# Runs a command and returns whether it succeeded, showing what it said. A bare
# external command that fails ends the whole script, so a step that has a next
# thing to try runs through here.
def attempt [program: string, ...arguments: string] {
    let result = (run-external $program ...$arguments | complete)
    let said = ($'($result.stdout)($result.stderr)' | str trim)
    if $said != '' { print $said }
    $result.exit_code == 0
}

# The mapping UDisks gives the unlocked LUKS container.
def mapping-name [config: record] { $'luks-($config.drive.luks_uuid)' }

def mounts-for [uuid: string] {
    let result = (^findmnt --json --list --source $'UUID=($uuid)' --output TARGET,SOURCE,FSTYPE,UUID,FSROOT | complete)
    if $result.exit_code == 1 { [] } else if $result.exit_code != 0 {
        error make {msg: 'Cannot inspect mount state.'}
    } else { $result.stdout | from json | get filesystems }
}

def mount-at [target: path] {
    let result = (^findmnt --json --mountpoint $target --output TARGET,SOURCE,FSTYPE,UUID,FSROOT | complete)
    if $result.exit_code == 1 { null } else if $result.exit_code != 0 {
        error make {msg: $'Cannot inspect mountpoint ($target).'}
    } else { $result.stdout | from json | get filesystems | first }
}

def root-mount [config: record] {
    let found = (mounts-for $config.drive.filesystem_uuid | where fsroot == '/')
    if ($found | length) != 1 { error make {msg: 'Expected exactly one mounted filesystem root. Run prepare or resolve duplicate mounts.'} }
    let root = ($found | first)
    if $root.fstype != $config.drive.filesystem_type { error make {msg: 'Unexpected filesystem type.'} }
    # Verify that the filesystem sits directly in the configured LUKS device.
    let tree = (checked lsblk ['--json' '--inverse' '--paths' '--output' 'NAME,UUID,FSTYPE' (device $config.drive.filesystem_uuid)] | from json)
    let block = ($tree.blockdevices | first)
    if ($block.children? | default [] | where uuid == $config.drive.luks_uuid | is-empty) {
        error make {msg: 'Filesystem is not backed by the configured LUKS UUID.'}
    }
    $root.target
}

def identity-report [config: record] {
    ['users' 'groups'] | each {|kind|
        $config | get $kind | each {|entry|
            let local = if $kind == 'users' {
                checked id ['-u' $entry.name] | into int
            } else {
                checked getent ['group' $entry.name] | split row ':' | get 2 | into int
            }
            {kind: $kind, name: $entry.name, disk_id: $entry.disk_id, local_id: $local, matches: ($entry.disk_id == $local)}
        }
    } | flatten
}

def require-identities [config: record] {
    let mismatches = (identity-report $config | where matches == false)
    if not ($mismatches | is-empty) {
        print $mismatches
        error make {msg: 'IDs differ. ID-mapped mounts require a disposable compatibility test before enabling this host; no ownership was changed.'}
    }
}

def prepare-drive [config: record] {
    if not ((device $config.drive.luks_uuid) | path exists) { error make {msg: 'Configured SSD is not connected.'} }
    # A mapping with no filesystem behind it is left from a drive that was pulled
    # while unlocked; it would make the unlock below fail with its own name.
    let leftover = ('/dev/mapper' | path join (mapping-name $config))
    if ($leftover | path exists) and not ((device $config.drive.filesystem_uuid) | path exists) {
        error make {msg: $'($leftover) is left from a drive that was pulled while unlocked. Run unmount --quiescent, with --force to free its name while a process still holds it. Restart the processes it lists, then mount again.'}
    }
    if not ((device $config.drive.filesystem_uuid) | path exists) {
        # UDisks owns the interactive passphrase prompt; no key enters this script.
        ^udisksctl unlock --block-device (device $config.drive.luks_uuid)
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Unlock failed; nothing else attempted.'} }
    }
    if (mounts-for $config.drive.filesystem_uuid | where fsroot == '/' | is-empty) {
        ^udisksctl mount --block-device (device $config.drive.filesystem_uuid)
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Filesystem mount failed; drive may remain unlocked.'} }
    }
    let root = (root-mount $config)
    print $'Prepared filesystem at ($root). No project paths changed.'
    $root
}

def assert-host-backup [config: record, project: record] {
    let parent = ($project.backup | path dirname)
    let mount = (checked findmnt ['--json' '--target' $parent '--output' 'UUID'] | from json | get filesystems | first)
    if $mount.uuid? == $config.drive.filesystem_uuid { error make {msg: 'Backup destination is on the portable SSD, not the host.'} }
    if ($project.backup | path exists) {
        let existing = (checked findmnt ['--json' '--target' $project.backup '--output' 'UUID'] | from json | get filesystems | first)
        if $existing.uuid? == $config.drive.filesystem_uuid { error make {msg: 'Backup repository is on the portable SSD.'} }
    }
}

def assert-project [config: record, project: record] {
    let mount = (mount-at $project.target)
    if $mount == null or $mount.uuid != $config.drive.filesystem_uuid or $mount.fsroot != $'/($project.directory)' {
        error make {msg: $'($project.target) is not the configured SSD project mount.'}
    }
}

def backup-projects [config: record] {
    for project in $config.projects {
        assert-project $config $project
        assert-host-backup $config $project
        backup-repository $project.target $project.backup | print
    }
}

def mount-projects [config: record] {
    require-identities $config
    # Check all destinations BEFORE unlocking or mounting anything.
    for project in $config.projects {
        if (mount-at $project.target) != null {
            assert-project $config $project
        } else if not (($project.target | path exists) and ((ls --all $project.target | length) == 0)) {
            error make {msg: $'($project.target) must be an existing empty destination. Active checkout left untouched; migration is a separate step.'}
        }
    }
    let root = (prepare-drive $config)
    for project in $config.projects {
        let source = ($root | path join $project.directory)
        if not ($source | path exists) { error make {msg: $'SSD project ($source) is missing. Migrate and verify it before mounting.'} }
        if ($source | path expand) != $source { error make {msg: 'SSD project source cannot traverse a symlink.'} }
        if (mount-at $project.target) == null {
            ^sudo mount --bind $source $project.target
            if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Project mount failed; inspect status before retrying.'} }
        }
        assert-project $config $project
    }
    backup-projects $config
    print 'Projects mounted and committed Git history backed up.'
}

def all-mounts [] {
    let result = (^findmnt --json --list --output TARGET,SOURCE,FSTYPE,UUID,FSROOT | complete)
    if $result.exit_code != 0 { error make {msg: 'Cannot inspect mount state.'} }
    $result.stdout | from json | get filesystems
}

# Mounts a pulled drive left behind: bound from the configured LUKS mapping,
# with no filesystem readable behind them (findmnt reports no UUID).
export def stale-mounts-in [config: record, mounts: list] {
    let source = $'/dev/mapper/(mapping-name $config)'
    $mounts | where {|mount|
        ($mount.source? | default '' | str starts-with $source) and (($mount.uuid? | default '') == '')
    }
}

# Whether the mapping's every disk has been unplugged: its sysfs links to them
# no longer resolve.
def mapping-is-dead [config: record] {
    let device = ('/dev/mapper' | path join (mapping-name $config) | path expand | path basename)
    let slaves = $'/sys/block/($device)/slaves'
    ^ls -1 $slaves | lines | all {|name| not ($slaves | path join $name | path exists) }
}

# How the kernel writes a block device number in each place a process can show
# it is still holding the device: a file watch's `sdev` (hex of major << 20 |
# minor), a mapped file's `major:minor` in hex, and a mount's decimal pair.
export def dev-codes [dev: string] {
    let parts = ($dev | split row ':' | each {|part| $part | into int })
    let hex = {|number| $number | format number | get lowerhex | str replace '0x' '' }
    {
        sdev: (do $hex (($parts | get 0) * 1048576 + ($parts | get 1)))
        maps: $'(do $hex ($parts | get 0) | fill --alignment right --character '0' --width 2):(do $hex ($parts | get 1) | fill --alignment right --character '0' --width 2)'
        mountinfo: $dev
    }
}

# Processes whose working directory or an open file on the dead filesystem now
# fails with an I/O error. A lazy detach hides the old path, so the error, not
# the path, is what names them.
def holders-by-error [] {
    let links = (glob '/proc/[0-9]*/cwd' | append (glob '/proc/[0-9]*/fd/*'))
    $links | chunks 2000 | each {|chunk|
        ^stat --dereference --format '%n' ...$chunk | complete | get stderr | lines
        | where {|line| $line | str contains 'Input/output error' }
        | each {|line| $line | parse --regex '/proc/(?<pid>[0-9]+)/' } | flatten
    } | flatten | each {|row| {pid: $row.pid, how: 'standing in a directory or holding a file open there'} }
}

# Processes whose /proc file for `kind` matches `pattern`.
def holders-by-match [kind: string, pattern: string, how: string] {
    glob $'/proc/[0-9]*/($kind)' | chunks 2000 | each {|chunk|
        ^grep -slE $pattern ...$chunk | complete | get stdout | lines
        | where {|line| $line != '' } | each {|path| {pid: ($path | path split | get 2), how: $how} }
    } | flatten
}

# Everything that still keeps the dead drive's device open, however it does it:
# the usual reason a mapping will not close, and the one `lsof` cannot show.
def holders [dev: string] {
    let codes = (dev-codes $dev)
    [
        (holders-by-error)
        (holders-by-match 'fdinfo/*' $'sdev:($codes.sdev)' 'watching it for changes')
        (holders-by-match 'maps' $' ($codes.maps) ' 'running or mapping a file from it')
        (holders-by-match 'mountinfo' $'^[0-9]+ [0-9]+ ($codes.mountinfo) ' 'still has it mounted in its own view of the filesystem')
    ] | flatten | group-by pid | items {|pid, rows|
        let owner = (try { ^stat -c %U $'/proc/($pid)' | str trim } catch { '' })
        let command = (try { open --raw $'/proc/($pid)/cmdline' | str replace --all (char nul) ' ' | str substring 0..99 } catch { '' })
        {pid: ($pid | into int), user: $owner, how: ($rows | get how | uniq | str join '; '), command: $command}
    } | sort-by pid
}

def last-backup [project: record] {
    let marker = ($project.backup | path join '.git' 'FETCH_HEAD')
    let newest = if ($marker | path exists) { $marker } else { $project.backup }
    if ($newest | path exists) {
        let modified = (ls --directory $newest | first | get modified | format date '%Y-%m-%d %H:%M')
        print $'  ($project.name): host backup at ($project.backup), last updated ($modified)'
    } else {
        print $'  ($project.name): no host backup exists at ($project.backup)'
    }
}

# The drive was pulled while unlocked and its project views were still bound.
# Nothing on it can be read, so there is nothing a lazy detach could lose and no
# final backup to make; say so, detach the dead views and close the dead mapping.
# `force` also frees the mapping's name while a process still holds it, so a
# replugged drive can be unlocked under it.
def clear-stale [config: record, stale: list, force: bool] {
    let name = (mapping-name $config)
    let node = ('/dev/mapper' | path join $name)
    let dev = (if ($node | path exists) { open --raw ($'/sys/block/($node | path expand | path basename)/dev') | str trim } else { '' })
    if ($node | path exists) and not (mapping-is-dead $config) {
        error make {msg: $'($name) still has a disk attached but its mounts are unreadable. This is not a pulled drive; inspect it by hand.'}
    }
    print 'The drive was removed while it was unlocked. Its files cannot be read, so no final backup is possible this run. Last host backups:'
    for project in $config.projects { last-backup $project }
    let targets = ($stale | get target | sort-by {|target| $target | str length } --reverse)
    for target in $targets {
        if not (attempt 'sudo' 'umount' '--lazy' $target) { error make {msg: $'Could not detach the stale mount ($target). Nothing else attempted.'} }
        print $'Detached stale mount ($target).'
    }
    if ($node | path exists) {
        # Its disk is gone, so a forced removal can only drop I/O that can never finish.
        if (attempt 'sudo' 'cryptsetup' 'close' $name) or (attempt 'sudo' 'dmsetup' 'remove' '--force' $name) {
            print $'Closed the dead mapping ($name).'
        } else {
            # Still open: processes that were standing on the drive. They cannot be stopped from
            # here; have the kernel drop the mapping when the last of them lets go.
            print 'Still holding the dead drive (processes of other users are not visible; run with sudo to see them):'
            print (holders $dev)
            if $force {
                # A device can be renamed while open, which frees the name `mount` unlocks under.
                let moved = $'($name)-dead-(date now | format date '%Y%m%d%H%M%S')'
                if not (attempt 'sudo' 'dmsetup' 'rename' $name $moved) { error make {msg: $'Could not rename the dead mapping ($name) out of the way. End or restart the processes above, then repeat this command.'} }
                attempt 'sudo' 'dmsetup' 'remove' '--deferred' $moved | ignore
                print $'The dead mapping is renamed ($moved) and goes when the last process above exits or restarts. Its name is free now. If mount still refuses, because the kernel may treat the old filesystem as a duplicate of the replugged one, end those processes first.'
            } else {
                if not (attempt 'sudo' 'dmsetup' 'remove' '--deferred' $name) { error make {msg: $'The dead mapping ($name) is held open and could not be scheduled for removal. End or restart the processes above, then repeat this command, or add --force to free the name now.'} }
                print $'The dead mapping ($name) is scheduled for removal and goes when the last process above exits or restarts. Mount only after that, or repeat with --force to free the name now.'
            }
        }
    }
}

# Dead mappings an earlier --force renamed aside, each with its device number.
def renamed-leftovers [config: record] {
    glob $'/dev/mapper/(mapping-name $config)-dead-*' | each {|node|
        {node: $node, dev: (open --raw $'/sys/block/($node | path expand | path basename)/dev' | str trim)}
    }
}

# Nothing is mounted: finish what is left, so the command can be repeated.
def settle-detached [config: record] {
    if (device $config.drive.filesystem_uuid | path exists) {
        if not (attempt 'udisksctl' 'lock' '--block-device' (device $config.drive.luks_uuid)) { error make {msg: 'LUKS locking failed. The filesystem is unmounted but the device may remain unlocked.'} }
        print 'The drive was unlocked but nothing was mounted; it is locked now.'
    } else {
        print 'Nothing is mounted and the drive is locked or disconnected. Nothing to do.'
    }
}

def unmount-projects [config: record, quiescent: bool, force: bool] {
    if not $quiescent { error make {msg: 'Finish builds, editors and agent work, then repeat with --quiescent. This confirms writers are stopped, not forcibly stopped.'} }
    let stale = (stale-mounts-in $config (all-mounts))
    # The mapping outlives its mounts, so a repeat picks up here once they are gone.
    let node = ('/dev/mapper' | path join (mapping-name $config))
    let dead = (($node | path exists) and (mapping-is-dead $config))
    if $force and ($stale | is-empty) and not $dead { print 'Nothing to force: no drive was pulled while mounted, so --force changes nothing.' }
    if not ($stale | is-empty) or $dead { clear-stale $config $stale $force }
    let attached = (not (mounts-for $config.drive.filesystem_uuid | where fsroot == '/' | is-empty)) or ($config.projects | any {|project| (mount-at $project.target) != null })
    if $attached { unmount-attached $config } else if ($stale | is-empty) and not $dead { settle-detached $config }
    for left in (renamed-leftovers $config) {
        print $'($left.node) is still waiting for these processes to let go; it disappears when they do:'
        print (holders $left.dev)
    }
}

def unmount-attached [config: record] {
    let root = (root-mount $config)
    # Refuse foreign/partial project state before touching anything.
    for project in $config.projects {
        if (mount-at $project.target) != null { assert-project $config $project }
        assert-host-backup $config $project
    }
    # Also supports recovery after only some project views were unmounted.
    for project in $config.projects {
        let source = ($root | path join $project.directory)
        if not ($source | path exists) { error make {msg: 'Missing project; final backup cannot be confirmed. Drive stays attached.'} }
        backup-repository $source $project.backup | print
    }
    let keep = 'Do not unplug the drive.'
    for project in ($config.projects | reverse) {
        if (mount-at $project.target) != null {
            if not (attempt 'sudo' 'umount' $project.target) {
                print $'Still using ($project.target):'
                attempt 'sudo' 'fuser' '-vm' $project.target | ignore
                error make {msg: $'Busy project unmount. No forced detach; the drive remains attached. ($keep) Close what is listed, then repeat.'}
            }
        }
    }
    if not (attempt 'sync') { error make {msg: $'Sync failed; the drive remains attached. ($keep)'} }
    if not (attempt 'udisksctl' 'unmount' '--block-device' (device $config.drive.filesystem_uuid)) { error make {msg: $'Filesystem unmount failed. The drive remains attached. ($keep)'} }
    if not (attempt 'udisksctl' 'lock' '--block-device' (device $config.drive.luks_uuid)) { error make {msg: $'LUKS locking failed. The filesystem is unmounted but the device may remain unlocked. ($keep)'} }
    print 'Final Git backup verified, project views unmounted, filesystem unmounted and LUKS locked.'
    print 'It is safe to unplug the drive now.'
}

def main [
    action: string # status, owners, prepare, mount, backup, unmount
    --config: path # Defaults to ../workspace-drive.toml beside scripts/
    --project: string # Back up only this enabled project (backup action only)
    --quiescent # Confirm writers are stopped before safe removal
    --force # unmount only: after a drive was pulled while mounted, free the dead mapping's name even while a process holds it
    --locked # Internal flock reentry
] {
    let file = ($config | default ($env.FILE_PWD | path join '..' 'workspace-drive.toml') | path expand)
    let loaded = (load-config $file)
    let manifest = if $project != null {
        if $action != 'backup' { error make {msg: '--project is supported only for backup; mount/unmount operate on the entire drive.'} }
        let selected = ($loaded.projects | where name == $project)
        if ($selected | length) != 1 { error make {msg: 'Expected exactly one enabled backup project.'} }
        $loaded | upsert projects $selected
    } else { $loaded }
    if $force and $action != 'unmount' { error make {msg: '--force is supported only for unmount, and only changes a drive that was pulled while mounted.'} }
    if $action not-in ['status' 'owners' 'prepare' 'mount' 'backup' 'unmount'] { error make {msg: 'Expected status, owners, prepare, mount, backup or unmount.'} }
    if $action in ['status' 'owners'] {
        if $action == 'owners' { identity-report $manifest } else {
            {connected: ((device $manifest.drive.luks_uuid) | path exists), unlocked: ((device $manifest.drive.filesystem_uuid) | path exists), mounts: (mounts-for $manifest.drive.filesystem_uuid), projects: ($manifest.projects | each {|project| {target: $project.target, mount: (mount-at $project.target)} })}
        }
    } else if ($manifest.projects | is-empty) and ($action in ['mount' 'backup' 'unmount']) {
        error make {msg: 'No projects enabled; refusing lifecycle changes.'}
    } else if not $locked {
        if not ($manifest.drive.lock_file | path exists) {
            error make {msg: 'Shared lifecycle lock is missing. See docs/WorkspaceDrive.md for one-time host setup.'}
        }
        let args = [$nu.current-exe $env.CURRENT_FILE $action '--config' $file '--locked'] | append (if $quiescent { ['--quiescent'] } else { [] }) | append (if $force { ['--force'] } else { [] }) | append (if $project != null { ['--project' $project] } else { [] })
        ^flock --nonblock $manifest.drive.lock_file ...$args
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Operation failed or another lifecycle operation is running. Inspect output/status; no automatic cleanup is attempted.'} }
    } else {
        match $action {
            'prepare' => { prepare-drive $manifest | ignore }
            'mount' => { mount-projects $manifest }
            'backup' => { backup-projects $manifest }
            'unmount' => { unmount-projects $manifest $quiescent $force }
        }
    }
}
