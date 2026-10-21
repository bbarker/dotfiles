# Process inspection uses metadata only: never command arguments or environments.
export def process-info [pid: int] {
    try {
        let row = (open --raw $'/proc/($pid)/stat' | parse --regex '(?s)^\d+ \((?<command>.*)\) (?<fields>.*)$' | first)
        let fields = ($row.fields | str trim | split row --regex '\s+')
        {pid: $pid, command: $row.command, parent: ($fields.1 | into int), state: $fields.0, started: $fields.19}
    } catch {
        if ($'/proc/($pid)' | path exists) { error make {msg: $'Cannot inspect process ($pid); refusing process cleanup.'} } else { null }
    }
}

def ancestry [pid: int] {
    if $pid <= 1 { [1] } else {
        let info = (process-info $pid)
        [$pid] | append (if $info == null { [] } else { ancestry $info.parent })
    }
}

export def project-holders [directories: list<path>] {
    # Scan open references rather than walking millions of build files with +D.
    # -Ki suppresses duplicate thread entries. Keep inspection warnings fatal.
    let result = (^lsof -nP -Ki -e /run/user/1000/doc -e /run/user/1000/gvfs -Fpcn | complete)
    if $result.exit_code not-in [0 1] or not ($result.stderr | str trim | is-empty) {
        error make {msg: $'Cannot inspect project references: ($result.stderr | str trim)'}
    }
    $result.stdout | split row --regex '(?m)^p' | skip 1 | each {|block|
        let rows = ($block | lines)
        let paths = ($rows | where {|row|
            $directories | any {|directory|
                $row == $'n($directory)' or ($row | str starts-with $'n($directory)/') or $row == ($'n($directory)' + ' (deleted)')
            }
        })
        if not ($paths | is-empty) {
            {pid: ($rows | first | into int), command: ($rows | where {|row| $row | str starts-with 'c'} | first | str substring 1..)}
        }
    } | compact | uniq-by pid
}

def protected-processes [] {
    let editors = (^ps -eo pid=,comm= | complete)
    if $editors.exit_code != 0 { error make {msg: 'Cannot identify protected editor processes.'} }
    let zed = ($editors.stdout | lines | parse --regex '^\s*(?<pid>\d+)\s+(?<command>.+)$'
        | where command =~ '(?i)(^|[./_-])zed([./_-]|$)' | get pid | into int)
    (ancestry $nu.pid) | append ($zed | each {|pid| ancestry $pid } | flatten) | uniq
}

def same-process [snapshot: record] {
    let current = (process-info $snapshot.pid)
    $current != null and $current.started == $snapshot.started and $current.state not-in ['Z' 'X']
}

def send-signal [snapshot: record, signal: string] {
    if (same-process $snapshot) {
        let result = (^kill --signal $signal -- ($snapshot.pid | into string) | complete)
        if $result.exit_code != 0 and (same-process $snapshot) {
            error make {msg: $'Cannot send ($signal) to PID ($snapshot.pid): ($result.stderr | str trim)'}
        }
    }
}

export def require-project-idle [directories: list<path>] {
    let holders = (project-holders $directories)
    if not ($holders | is-empty) {
        print ($holders | table)
        error make {msg: 'Project references remain. Close them manually or use --kill after saving your work.'}
    }
}

export def release-project-holders [directories: list<path>] {
    let holders = (project-holders $directories)
    if not ($holders | is-empty) {
        let protected = (protected-processes)
        let blocked = ($holders | where {|holder| $holder.pid in $protected })
        # Check all targets first: no partial cleanup if an editor/helper is held.
        if not ($blocked | is-empty) {
            print ($blocked | table)
            error make {msg: 'Protected process holds the project: Zed or the invoking process chain. Release its references manually; nothing was signalled.'}
        }
        print 'Closing these project holders: TERM, then KILL after 5 seconds if needed.'
        print ($holders | table)
        let snapshots = ($holders | each {|holder| process-info $holder.pid } | compact)
        for snapshot in $snapshots { send-signal $snapshot 'TERM' }
        for attempt in 1..25 {
            if ($snapshots | any {|snapshot| same-process $snapshot }) { sleep 200ms }
        }
        let survivors = ($snapshots | where {|snapshot| same-process $snapshot })
        for snapshot in $survivors { send-signal $snapshot 'KILL' }
        if not ($survivors | is-empty) { sleep 200ms }
        # Re-scan once. Do not kill replacements or a restarting service forever.
        require-project-idle $directories
    }
}
