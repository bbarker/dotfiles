#!/usr/bin/env nu
# Read-only host view of the configured SSD and project bind mounts. No sudo.
def queried [program: string, arguments: list<string>, --allow-absent] {
    let result = (run-external $program ...$arguments | complete)
    if $allow_absent and $result.exit_code == 1 { [] } else if $result.exit_code != 0 {
        error make {msg: $'($program) failed: ($result.stderr | str trim)'}
    } else { $result.stdout | from json }
}

def devices [nodes: list] {
    $nodes | each {|node|
        [{device: $node.name, parent: ($node.pkname? | default ''), type: $node.type,
          filesystem: ($node.fstype? | default ''), uuid: ($node.uuid? | default ''),
          size: $node.size, model: ($node.model? | default ''), transport: ($node.tran? | default '')}]
        | append (devices ($node.children? | default []))
    } | flatten
}

def ancestors [all: list, device: string] {
    let matches = ($all | where device == $device)
    if ($matches | is-empty) { [] } else {
        let entry = ($matches | first)
        [$entry] | append (if $entry.parent == '' { [] } else { ancestors $all $entry.parent })
    }
}

def main [
    --config: path # Defaults to workspace-drive.toml in the dotfiles root
    --json # Return structured status instead of formatted tables
] {
    let file = ($config | default ($env.FILE_PWD | path join '..' 'workspace-drive.toml'))
    let manifest = (open $file)
    let all = (devices (queried lsblk ['--json' '--paths' '--output' 'NAME,PKNAME,TYPE,FSTYPE,UUID,SIZE,MODEL,TRAN'] | get blockdevices))
    let encrypted = ($all | where uuid == $manifest.drive.luks_uuid)
    let filesystems = ($all | where uuid == $manifest.drive.filesystem_uuid)
    let chain = if ($filesystems | is-empty) {
        if ($encrypted | is-empty) { [] } else { ancestors $all $encrypted.0.device }
    } else { ancestors $all $filesystems.0.device }
    let found = (queried findmnt ['--json' '--list' '--source' $'UUID=($manifest.drive.filesystem_uuid)' '--output' 'TARGET,SOURCE,FSTYPE,UUID,FSROOT'] --allow-absent)
    let mounts = ($found.filesystems? | default [])
    let status = if ($encrypted | is-empty) { 'disconnected' } else if ($filesystems | is-empty) { 'locked' } else if ($mounts | is-empty) { 'unlocked, not mounted' } else { 'mounted' }
    let projects = ($manifest.projects | each {|project|
        let found = (queried findmnt ['--json' '--mountpoint' $project.target '--output' 'TARGET,SOURCE,FSTYPE,UUID,FSROOT'] --allow-absent)
        let mounted = ($found.filesystems? | default [])
        let enabled = ($project.enabled? | default true)
        let status = if ($mounted | is-empty) {
            if $enabled { 'not mounted' } else { 'deferred' }
        } else if $mounted.0.uuid == $manifest.drive.filesystem_uuid and $mounted.0.fsroot == $'/($project.directory)' and $mounted.0.fstype == $manifest.drive.filesystem_type {
            'mounted'
        } else { 'DIFFERENT MOUNT' }
        {project: $project.name, enabled: $enabled, status: $status, target: $project.target,
         source: (if ($mounted | is-empty) { '' } else { $mounted.0.source }),
         filesystem_root: (if ($mounted | is-empty) { '' } else { $mounted.0.fsroot })}
    })
    let report = {status: $status, luks_uuid: $manifest.drive.luks_uuid,
                  filesystem_uuid: $manifest.drive.filesystem_uuid, devices: $chain,
                  mounts: $mounts, projects: $projects}
    if $json { $report | to json } else {
        print $'Workspace SSD: ($status)'
        print $'LUKS UUID: ($report.luks_uuid)'
        print $'Filesystem UUID: ($report.filesystem_uuid)'
        print "\nSSD device chain (filesystem -> physical disk)"
        if ($chain | is-empty) { print 'No configured SSD detected.' } else {
            for entry in $chain {
                print $'  ($entry.device)  [($entry.type), ($entry.filesystem), ($entry.size)] ($entry.model) ($entry.transport)'
            }
        }
        print "\nSSD mountpoints"
        if ($mounts | is-empty) { print 'None.' } else {
            for entry in $mounts { print $'  ($entry.target) -> ($entry.source)  [($entry.fstype), root=($entry.fsroot)]' }
        }
        print "\nProject binds"
        for project in $projects {
            print $'  ($project.project): ($project.status) [enabled=($project.enabled)]'
            print $'    ($project.target)'
            if $project.source != '' { print $'    -> ($project.source)' }
        }
        print "\nStatus reflects the current mount namespace; run on the host for the host view."
    }
}
