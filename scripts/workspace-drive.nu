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

def unmount-projects [config: record, quiescent: bool] {
    if not $quiescent { error make {msg: 'Finish builds, editors and agent work, then repeat with --quiescent. This confirms writers are stopped, not forcibly stopped.'} }
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
    for project in ($config.projects | reverse) {
        if (mount-at $project.target) != null {
            ^sudo umount $project.target
            if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Busy/failed project unmount. No forced detach; drive remains attached.'} }
        }
    }
    ^sync
    if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Sync failed; drive remains attached.'} }
    ^udisksctl unmount --block-device (device $config.drive.filesystem_uuid)
    if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Filesystem unmount failed. Drive remains attached.'} }
    ^udisksctl lock --block-device (device $config.drive.luks_uuid)
    if $env.LAST_EXIT_CODE != 0 { error make {msg: 'LUKS locking failed. Filesystem is unmounted but device may remain unlocked.'} }
    print 'Final Git backup verified, project views unmounted, filesystem unmounted and LUKS locked.'
}

def main [
    action: string # status, owners, prepare, mount, backup, unmount
    --config: path # Defaults to ../workspace-drive.toml beside scripts/
    --project: string # Back up only this enabled project (backup action only)
    --quiescent # Confirm writers are stopped before safe removal
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
        let args = [$nu.current-exe $env.CURRENT_FILE $action '--config' $file '--locked'] | append (if $quiescent { ['--quiescent'] } else { [] }) | append (if $project != null { ['--project' $project] } else { [] })
        ^flock --nonblock $manifest.drive.lock_file ...$args
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Operation failed or another lifecycle operation is running. Inspect output/status; no automatic cleanup is attempted.'} }
    } else {
        match $action {
            'prepare' => { prepare-drive $manifest | ignore }
            'mount' => { mount-projects $manifest }
            'backup' => { backup-projects $manifest }
            'unmount' => { unmount-projects $manifest $quiescent }
        }
    }
}
