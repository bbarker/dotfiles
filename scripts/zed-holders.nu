#!/usr/bin/env nu
# What a running Zed holds, for when a drive or directory will not let go.
# Closing every file is not enough: each folder of a window's project stays open
# and watched for changes until it is removed from the project, and Zed keeps a
# folder after it is deleted or its drive is pulled.

# Zed's state for the stable channel: open windows and their project folders.
export def zed-state [] {
    ($env.XDG_DATA_HOME? | default ('~/.local/share' | path expand)) | path join 'zed' 'db' '0-stable'
}

export def zed-pids [] {
    ^ps -eo pid=,comm= | lines | parse --regex '^\s*(?<pid>\d+)\s+(?<command>.+)$'
    | where command =~ '^zed' | get pid | into int
}

# Each path's type and device, or the reason it cannot be read. One stat call
# for all of them; a path on a dead drive fails with an I/O error.
def stat-paths [paths: list<string>] {
    if ($paths | is-empty) { return [] }
    let result = (^stat --dereference --format '%n|%F|%Hd:%Ld' ...$paths | complete)
    let found = ($result.stdout | lines | parse '{path}|{kind}|{device}' | insert problem '')
    let failed = ($result.stderr | lines | parse --regex "cannot statx? '(?<path>.*)': (?<problem>.*)$"
        | insert kind '' | insert device '')
    $found | append $failed
}

# Where a `major:minor` device is mounted and what it is called, so a device
# that nothing mounts any more (a pulled or unmounted drive) stands out.
def describe-device [device: string, mounts: table] {
    let sys = $'/sys/dev/block/($device)'
    let name = if ($sys | path join 'dm' 'name' | path exists) {
        open --raw ($sys | path join 'dm' 'name') | str trim
    } else if ($sys | path exists) { $sys | path expand | path basename } else { '' }
    {name: $name, mounted: ($mounts | where device == $device | get target | str join ' ')}
}

def mounts [] {
    ^findmnt --list --noheadings --output 'MAJ:MIN,TARGET' | lines
    | parse --regex '^\s*(?<device>\S+)\s+(?<target>.*)$'
}

# The project folders of the windows in Zed's current session. Reads a copy of
# the state database so the running editor's own copy is never locked.
export def zed-projects [state: path] {
    let copy = (^mktemp -d -t zed-holders.XXXXXX | str trim)
    let rows = (try {
        for name in ['db.sqlite' 'db.sqlite-wal' 'db.sqlite-shm'] {
            if ($state | path join $name | path exists) { cp ($state | path join $name) $copy }
        }
        let db = (open ($copy | path join 'db.sqlite'))
        let session = ($db | query db "select value from kv_store where key = 'session_id'" | get value)
        $db | query db 'select workspace_id, paths from workspaces where session_id = ? and remote_connection_id is null' -p $session
    } catch {|problem|
        rm -rf $copy
        error make {msg: $'Cannot read Zed state at ($state): ($problem.msg)'}
    })
    rm -rf $copy
    let folders = ($rows | each {|row|
        $row.paths | lines | where {|path| $path != '' } | each {|path| {window: $row.workspace_id, folder: $path} }
    } | flatten)
    let found = (stat-paths ($folders | get folder))
    let mounts = (mounts)
    $folders | each {|folder|
        let info = ($found | where path == $folder.folder | first)
        $folder | merge {
            state: (if $info.problem == '' { 'ok' } else { $info.problem })
            device: $info.device
            mounted: (if $info.device == '' { '' } else { (describe-device $info.device $mounts).mounted })
        }
    }
}

# Directories each process keeps open that are deleted or can no longer be read.
# Deleted plain files (memfd buffers, temporary files) are left out as noise.
export def broken-directories [pids: list<int>] {
    $pids | each {|pid|
        # Read the links as text: resolving a deleted directory's link fails.
        let targets = (try { ls --long $'/proc/($pid)/fd' | select name target | rename link } catch { [] }
            | append {link: $'/proc/($pid)/cwd', target: (^readlink $'/proc/($pid)/cwd' | complete | get stdout | str trim)})
        let found = (stat-paths ($targets | get link))
        $targets | each {|entry|
            let info = ($found | where path == $entry.link | first)
            let deleted = ($entry.target | str ends-with ' (deleted)')
            if $info.problem != '' or ($deleted and $info.kind == 'directory') {
                {pid: $pid, link: ($entry.link | path basename), target: $entry.target, problem: (if $info.problem != '' { $info.problem } else { 'deleted' })}
            }
        } | compact
    } | flatten
}

# Each process's file watches counted by device. Watches on a device that is no
# longer mounted are what keep a pulled drive's mapping busy.
export def watches [pids: list<int>] {
    let mounts = (mounts)
    $pids | each {|pid|
        glob $'/proc/($pid)/fdinfo/*'
        | each {|info| try { open --raw $info | lines | where {|line| $line | str starts-with 'inotify' } } catch { [] } }
        | flatten | parse --regex 'sdev:(?<sdev>[0-9a-f]+)'
        | group-by sdev | items {|sdev, rows|
            # The kernel writes a watch's device as hex of major << 20 | minor.
            let number = ($sdev | into int --radix 16)
            let device = $'($number | bits shr 20):($number | bits and 1048575)'
            {pid: $pid, device: $device} | merge (describe-device $device $mounts) | insert watches ($rows | length)
        }
    } | flatten | sort-by pid device
}

# Shows what each running Zed holds that can keep a drive busy. A project folder
# that is not `ok`, a broken directory, or watches on a device with nothing
# mounted mean a window still has a folder from that drive in its project: open
# the Project Panel there and use Remove from Project on it, or close the window.
def main [] {
    let pids = (zed-pids)
    if ($pids | is-empty) { print 'Zed is not running.'; return }
    print 'Project folders of open Zed windows:'
    print (zed-projects (zed-state))
    let broken = (broken-directories $pids)
    if ($broken | is-empty) {
        print 'No deleted or unreadable directories held open.'
    } else {
        print 'Deleted or unreadable directories held open:'
        print $broken
    }
    print 'File watches by device:'
    print (watches $pids)
    print ''
    print 'To release a folder: find its window by the folders listed with the same window number, open the'
    print 'Project Panel there, right-click the folder and choose Remove from Project. Closing that window or'
    print 'quitting Zed also releases it; closing its files does not.'
}
