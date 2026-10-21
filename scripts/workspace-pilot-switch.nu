#!/usr/bin/env nu
# One-time selected-project cutover. Retains the original; cleanup is opt-in.
use workspace-rsync.nu XATTR_FILTERS
use workspace-project.nu migration-project
use workspace-processes.nu [require-project-idle release-project-holders]
def checked [program: string, arguments: list<string>] {
    let result = (run-external $program ...$arguments | complete)
    if $result.exit_code != 0 { error make {msg: $'($program) failed: ($result.stderr | str trim)'} }
    $result.stdout | str trim
}

def acl-inventory [directory: path] {
    checked getfacl ['--recursive' '--absolute-names' '--numeric' $directory]
    | str replace --all $'# file: ($directory)' '# file: PROJECT'
    | split row "\n\n"
    | each {|block| $block | str trim }
    | where {|block| not ($block | is-empty) }
    | sort
}

def main [
    --project: string = 'shoggothox' # Enabled project from workspace-drive.toml
    --switch-to-ssd # Sync, verify and switch the selected project; pause writers first
    --verify-only # Report copy differences without syncing or switching directories
    --kill # Terminate remaining project holders; protects Zed and this command's ancestors
    --locked # Internal lifecycle-lock reentry
] {
    if $switch_to_ssd == $verify_only { error make {msg: 'Choose exactly one of --switch-to-ssd or --verify-only. Keep writers paused.'} }
    if $kill and $verify_only { error make {msg: '--kill requires --switch-to-ssd; verification-only never terminates processes.'} }
    let migration = (migration-project $project)
    if (checked id ['-u']) != '0' { error make {msg: 'Run on the host with sudo; no project was changed.'} }
    let scripts = '/var/workspace/dotfiles/scripts'
    let config = $migration.config
    let source = $migration.source
    let rollback = $migration.rollback
    let uuid = $config.drive.filesystem_uuid
    if not $locked {
        if not ($config.drive.lock_file | path exists) { error make {msg: 'Shared lifecycle lock is missing.'} }
        let action = if $verify_only { '--verify-only' } else { '--switch-to-ssd' }
        let cleanup = if $kill { ['--kill'] } else { [] }
        ^flock --nonblock $config.drive.lock_file $nu.current-exe $env.CURRENT_FILE $action --project $project --locked ...$cleanup
        if $env.LAST_EXIT_CODE != 0 { error make {msg: 'Operation did not complete. Read the preceding error and inspect status; original retained.'} }
    } else {
        # Existing lifecycle validation checks numeric identities and LUKS backing.
        checked $nu.current-exe [($scripts | path join 'workspace-drive.nu') 'owners'] | print
        for entry in $config.users {
            if (checked id ['-u' $entry.name] | into int) != $entry.disk_id { error make {msg: 'User IDs differ; no cutover.'} }
        }
        for entry in $config.groups {
            if (checked getent ['group' $entry.name] | split row ':' | get 2 | into int) != $entry.disk_id { error make {msg: 'Group IDs differ; no cutover.'} }
        }
        if ($rollback | path exists --no-symlink) { error make {msg: 'Rollback path already exists; inspect prior cutover before retrying.'} }
        let roots = (checked findmnt ['--json' '--list' '--source' $'UUID=($uuid)' '--output' 'TARGET,FSTYPE,FSROOT'] | from json | get filesystems | where fsroot == '/')
        if ($roots | length) != 1 or $roots.0.fstype != 'xfs' { error make {msg: 'Expected one mounted XFS SSD root.'} }
        let tree = (checked lsblk ['--json' '--inverse' '--paths' '--output' 'NAME,UUID' $'/dev/disk/by-uuid/($uuid)'] | from json | get blockdevices | first)
        if ($tree.children? | default [] | where uuid == $config.drive.luks_uuid | is-empty) { error make {msg: 'Unexpected LUKS backing.'} }
        let destination = ($roots.0.target | path join $migration.project.directory)
        for directory in [$source $destination] {
            if ($directory | path expand --strict) != $directory { error make {msg: 'Project path traverses a symlink.'} }
        }
        let nested = (checked findmnt ['--list' '--output' 'TARGET' '--noheadings'] | lines | where {|target| $target == $source or ($target | str starts-with $'($source)/') or ($target | str starts-with $'($destination)/') or $target == $destination })
        if not ($nested | is-empty) { error make {msg: 'Unexpected project or nested mounts; review before switching.'} }
        if $kill { release-project-holders [$source $destination] } else { require-project-idle [$source $destination] }
        if $switch_to_ssd {
        print 'Final synchronization; source and original checkout are retained.'
        checked rsync ['-aHAX' '--numeric-ids' '--one-file-system' '--info=stats2' ...$XATTR_FILTERS '--' $'($source)/' $'($destination)/'] | print
        # Explicit ACL restore is necessary for this observed copy workflow.
        checked $nu.current-exe [($scripts | path join 'workspace-pilot-copy.nu') '--restore-acls' '--project' $project '--locked'] | print
        }
        print 'Verifying file contents and metadata. No file contents or hashes are printed.'
        let forward = (checked rsync ['-aHAXnc' '--numeric-ids' '--one-file-system' '--out-format=%i %n' ...$XATTR_FILTERS '--' $'($source)/' $'($destination)/'])
        let reverse = (checked rsync ['-rln' '--size-only' '--out-format=%i %n' '--' $'($destination)/' $'($source)/'])
        if not ($forward | is-empty) or not ($reverse | is-empty) {
            if not ($forward | is-empty) { print 'Source -> SSD differences (change codes and paths):'; print $forward }
            if not ($reverse | is-empty) { print 'SSD -> source differences (change codes and paths):'; print $reverse }
            error make {msg: 'Copies differ or SSD contains stale entries. No cutover or deletion occurred; review the differences.'}
        }
        if (acl-inventory $source) != (acl-inventory $destination) { error make {msg: 'Ownership/mode/ACL inventories differ; no cutover.'} }
        checked git ['-c' $'safe.directory=($destination)' '-C' $destination 'fsck' '--connectivity-only' '--no-dangling'] | ignore
        if $verify_only {
            print 'VERIFICATION PASSED: contents, metadata, ACLs and Git connectivity agree. No syncing or directory switch performed.'
        } else {
        # Processes appearing during verification require review, not another kill.
        require-project-idle [$source $destination]
        # Caller must keep writers paused; lsof is a point-in-time check, not a lock.
        checked mv ['--no-clobber' '--' $source $rollback] | ignore
        if ($source | path exists --no-symlink) or not ($rollback | path exists) { error make {msg: 'Original directory rename did not complete.'} }
        try {
            checked install ['-d' '-o' 'root' '-g' 'root' '-m' '0555' $source] | ignore
            checked setfacl ['-b' '-k' $source] | ignore
            checked chmod ['0555' $source] | ignore
            checked mount ['--bind' $destination $source] | ignore
        } catch {|problem|
            let mounted = (^findmnt --mountpoint $source | complete)
            if $mounted.exit_code == 1 {
                if ($source | path exists) { checked rmdir ['--' $source] | ignore }
                checked mv ['--no-clobber' '--' $rollback $source] | ignore
            }
            error make {msg: $'Mount setup failed: ($problem.msg). Inspect paths and status before retrying.'}
        }
        let mounted = (checked findmnt ['--json' '--mountpoint' $source '--output' 'UUID,FSROOT'] | from json | get filesystems | first)
        if $mounted.uuid != $uuid or $mounted.fsroot != $'/($migration.project.directory)' { error make {msg: $'Unexpected project mount; original retained at ($rollback). Do not resume writers.'} }
        # Preserve ordinary backup ownership by fetching as the existing agent user.
        checked runuser ['-u' 'borg' '--' $nu.current-exe ($scripts | path join 'workspace-drive.nu') 'backup' '--project' $project '--locked'] | print
        print $'CUTOVER COMPLETE: ($source) is on the SSD; original retained at ($rollback). Git backup verified. Leave the SSD attached.'
        }
    }
}
