#!/usr/bin/env nu
# Initial copy only. Never switches mounts, deletes source files or stops processes.
use workspace-rsync.nu XATTR_FILTERS
use workspace-project.nu migration-project
def checked [program: string, arguments: list<string>] {
    let result = (run-external $program ...$arguments | complete)
    if $result.exit_code != 0 { error make {msg: $'($program) failed: ($result.stderr | str trim)'} }
    $result.stdout | str trim
}

def main [
    --project: string = 'shoggothox' # Enabled project from workspace-drive.toml
    --copy # Create the first SSD copy; requires root. Writers may remain active.
    --restore-acls # Restore source ACL metadata to the existing initial copy only
    --locked # Internal lifecycle-lock reentry
] {
    if $copy == $restore_acls { error make {msg: 'Choose exactly one of --copy or --restore-acls. No cutover is performed.'} }
    let migration = (migration-project $project)
    if (checked id ['-u']) != '0' { error make {msg: 'Run on the host with sudo to preserve mixed ownership and ACLs.'} }
    let lock = $migration.config.drive.lock_file
    if not $locked {
        if not ($lock | path exists) { error make {msg: 'Existing shared lifecycle lock is required.'} }
        let action = if $copy { '--copy' } else { '--restore-acls' }
        ^flock --nonblock $lock $nu.current-exe $env.CURRENT_FILE $action --project $project --locked
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Initial copy failed or lifecycle lock was busy. Original checkout is unchanged.'} }
    } else {
        let uuid = $migration.config.drive.filesystem_uuid
        let luks = $migration.config.drive.luks_uuid
        let source = $migration.source
        let roots = (checked findmnt ['--json' '--list' '--source' $'UUID=($uuid)' '--output' 'TARGET,FSTYPE,FSROOT'] | from json | get filesystems | where fsroot == '/')
        if ($roots | length) != 1 { error make {msg: 'Expected one mounted SSD filesystem root.'} }
        let root = ($roots | first)
        if $root.fstype != 'xfs' { error make {msg: 'Expected XFS.'} }
        let tree = (checked lsblk ['--json' '--inverse' '--paths' '--output' 'NAME,UUID,FSTYPE' $'/dev/disk/by-uuid/($uuid)'] | from json | get blockdevices | first)
        if ($tree.children? | default [] | where uuid == $luks | is-empty) { error make {msg: 'Unexpected encryption backing device.'} }
        if ($source | path expand --strict) != $source { error make {msg: 'Source must be the original directory, not a symlink.'} }
        let source_mount = (checked findmnt ['--json' '--target' $source '--output' 'TARGET,UUID'] | from json | get filesystems | first)
        if $source_mount.uuid == $uuid { error make {msg: 'Source is already on the SSD.'} }
        let nested = (^findmnt --list --output TARGET --noheadings | lines | where {|target| $target == $source or ($target | str starts-with $'($source)/') })
        if not ($nested | is-empty) { error make {msg: 'Source contains mounts; review them before copying.'} }
        let parent = ($root.target | path join 'projects')
        let destination = ($root.target | path join $migration.project.directory)
        if ($parent | path exists --no-symlink) and (($parent | path expand --strict) != $parent) { error make {msg: 'Project parent must not be a symlink.'} }
        if $copy and ($destination | path exists --no-symlink) { error make {msg: 'SSD pilot destination already exists. Review the previous copy before retrying; nothing was overwritten.'} }
        if $restore_acls {
            if not ($destination | path exists) or (($destination | path expand --strict) != $destination) { error make {msg: 'Expected the existing SSD pilot directory, not a symlink.'} }
            let destination_mount = (checked findmnt ['--json' '--target' $destination '--output' 'UUID'] | from json | get filesystems | first)
            if $destination_mount.uuid != $uuid { error make {msg: 'ACL destination is not on the configured SSD.'} }
        }
        if $copy {
        let available = (checked df ['--block-size=1' '--output=avail' $root.target] | lines | last | str trim | into int)
        let needed = (checked du ['--summarize' '--block-size=1' $source] | split row (char tab) | first | into int)
        if $available < ($needed * 1.2) { error make {msg: 'Insufficient free space including copy headroom.'} }
        print (checked xfs_info [$root.target])
        # Narrow, nonrecursive traversal grants; copied project ACLs remain intact.
        checked setfacl ['-m' 'g:workspace:--x' ($root.target | path dirname)] | ignore
        checked setfacl ['-m' 'g:workspace:--x' $root.target] | ignore
        if not ($parent | path exists) { checked install ['-d' '-o' 'root' '-g' 'workspace' '-m' '0750' $parent] | ignore }
        print $'Initial live copy: ($source) -> ($destination)'
        ^rsync -aHAX --numeric-ids --one-file-system --info=stats2 ...$XATTR_FILTERS -- $'($source)/' $'($destination)/'
        let result = $env.LAST_EXIT_CODE
        if $result not-in [0 24] { error make {msg: $'rsync exited ($result). Partial destination retained; original is unchanged.'} }
        if $result == 24 { print 'Some source files vanished during the live copy; final synchronization is still required.' }
        }
        # Preserve named entries explicitly; verify after applying, not just rsync exit.
        let metadata = (checked getfacl ['--recursive' '--absolute-names' '--numeric' $source])
        let mapped = ($metadata | str replace --all $'# file: ($source)' $'# file: ($destination)')
        let restored = ($mapped | ^setfacl --restore=- | complete)
        if $restored.exit_code != 0 { error make {msg: $'ACL restoration failed: ($restored.stderr | str trim)'} }
        print 'Source ownership, mode and ACL metadata restored on the SSD copy. Verify with a fresh metadata comparison.'
        print 'Initial copy only. Writers may have changed files. No cutover or final verification has occurred. Leave the drive mounted.'
    }
}
