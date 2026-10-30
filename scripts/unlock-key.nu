#!/usr/bin/env nu
# Linux: Nushell, GNU coreutils, setfacl, and (unless --no-timer) a running cron daemon.
# Never reads the file's contents. Parent directories must already allow group traversal.
# Cron checks once a minute; an overdue job runs when cron next runs after downtime.
# Keep this script at its installed path until its timers finish.

def checked [program: string, arguments: list<string>] {
    let result = (run-external $program ...$arguments | complete)
    if $result.exit_code != 0 {
        error make {msg: $'($program) failed: ($result.stderr | str trim)'}
    }
    $result.stdout | str trim
}

def file-identity [file: path] {
    if ($file | path type) != 'file' {
        error make {msg: 'Expected a regular file, not a directory or symbolic link.'}
    }
    let metadata = (checked stat ['-c' '%u:%d:%i' '--' $file] | split row ':')
    if $metadata.0 != (checked id ['-u']) {
        error make {msg: 'The file must be owned by the current user.'}
    }
    $metadata | str join ':'
}

def marker-for [file: path] { $'# unlock-key:($file | hash sha256):' }

def read-cron [] {
    let result = (^crontab -l | complete)
    if $result.exit_code == 0 { $result.stdout } else if (
        $result.exit_code == 1 and ($result.stderr | str trim | str starts-with 'no crontab for ')
    ) { '' } else {
        error make {msg: $'Cannot read crontab: ($result.stderr | str trim). Use --no-timer for manual-only access.'}
    }
}

def without-job [table: string, marker: string] {
    $table | lines | where {|line| not ($line | str contains $marker) }
}

def write-cron [rows: list<string>] {
    let text = if ($rows | is-empty) { '' } else { ($rows | str join (char nl)) + (char nl) }
    let result = ($text | ^crontab - | complete)
    if $result.exit_code != 0 { error make {msg: $'Cannot update crontab: ($result.stderr | str trim)'} }
}

def remove-job [marker: string] {
    let table = (read-cron)
    if ($table | str contains $marker) { write-cron (without-job $table $marker) }
}

def lock-file [file: path] {
    checked chmod ['0600' '--' $file] | ignore
    checked setfacl ['--remove-all' '--' $file] | ignore
}

# Cron passes commands through /bin/sh, then treats percent specially even in quotes.
def shell-quote [value: string] {
    "'" + ($value | str replace --all "'" "'\"'\"'") + "'"
}

# Internal cron entry point. A generation token makes replaced/cancelled timers inert.
def 'main expire' [file: path, deadline: int, identity: string, token: string] {
    if (date now | into int) >= $deadline {
        let marker = (marker-for $file) + $token
        if (read-cron | lines | any {|line| $line | str ends-with $marker }) {
            # Never chmod a replacement file or a symbolic link left at the old path.
            let current = (try { file-identity $file } catch { null })
            if $current == $identity { lock-file $file }
            remove-job $marker
        }
    }
}

# Grant a group read access, then automatically return to owner-only access.
# Examples:
#   nu unlock-key.nu /path/to/file
#   nu unlock-key.nu /path/to/file --group workspace --after 30min
#   nu unlock-key.nu /path/to/file --relock
#   nu unlock-key.nu /path/to/file --no-timer
# Modes are deliberately 0640 / 0600, not a restoration of earlier permissions.
def main [
    file: path
    --group (-g): string = 'workspace' # Group receiving read access; chgrp must be permitted.
    --after: duration = 2hr           # Relock after this duration, within cron's minute resolution.
    --relock                         # Lock immediately and cancel this file's timer if accessible.
    --no-timer                       # Explicit manual-only access when cron is unavailable.
] {
    let target = ($file | path expand --no-symlink)
    let identity = (file-identity $target)
    let marker = (marker-for $target)
    if $relock {
        lock-file $target
        # Permission tightening must succeed even if cron is unavailable.
        try { remove-job $marker } catch {|failure| print --stderr $'Locked; timer cleanup unavailable: ($failure.msg)' }
        print $'Locked: ($target) [0600]'
    } else {
        if $after <= 0sec { error make {msg: '--after must be positive.'} }
        checked getent ['group' $group] | ignore
        let deadline = ((date now) + $after | into int)
        let token = (random uuid)
        if not $no_timer {
            let table = (read-cron)
            let arguments = [
                $nu.current-exe '--no-config-file' ($env.FILE_PWD | path join 'unlock-key.nu')
                'expire' $target ($deadline | into string) $identity $token
            ]
            if ($arguments | any {|argument| $argument =~ '[\r\n]' }) {
                error make {msg: 'Cron cannot safely represent a path containing a newline.'}
            }
            let command = ($arguments | each {|argument| shell-quote $argument } | str join ' ' | str replace --all '%' '\%')
            let row = $'* * * * * ($command) ($marker)($token)'
            write-cron ((without-job $table $marker) | append $row)
        }
        try {
            # Tighten first: partial failures leave the file locked.
            lock-file $target
            checked chgrp ['--' $group $target] | ignore
            checked chmod ['0640' '--' $target] | ignore
        } catch {|failure|
            try { lock-file $target } catch { print --stderr 'Could not restore 0600; check file permissions.' }
            if not $no_timer { try { remove-job ($marker + $token) } catch { null } }
            error make {msg: $failure.msg}
        }
        if $no_timer {
            # Cancel an older timer when intentionally switching to manual-only access.
            try { remove-job $marker } catch {|failure| print --stderr $'Timer cleanup unavailable: ($failure.msg)' }
        }
        let expiry = if $no_timer { 'manual relock required' } else { $'relocks after ($after), cron must be running' }
        print $'Readable by group ($group): ($target) [0640]; ($expiry).'
    }
}
