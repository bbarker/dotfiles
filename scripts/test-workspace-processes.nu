use std/assert
use workspace-processes.nu [process-info project-holders release-project-holders]

def spawn-holder [directory: path, program: path, --ignore-term] {
    # Deliberate disposable external processes; all arguments passed separately.
    let script = if $ignore_term {
        'cd "$1" || exit; trap "" TERM; "$2" 60 </dev/null >/dev/null 2>&1 & printf "%s\n" "$!"'
    } else {
        'cd "$1" || exit; "$2" 60 </dev/null >/dev/null 2>&1 & printf "%s\n" "$!"'
    }
    let spawned = (^sh -c $script fixture $directory $program | complete)
    if $spawned.exit_code != 0 { error make {msg: $spawned.stderr} }
    let pid = ($spawned.stdout | str trim | into int)
    sleep 100ms
    process-info $pid
}

def alive [snapshot: record] {
    let current = (process-info $snapshot.pid)
    $current != null and $current.started == $snapshot.started and $current.state not-in ['Z' 'X']
}

def main [] {
    let fixture = (^mktemp -d /tmp/workspace-process-test.XXXXXX | str trim)
    let target = ($fixture | path join 'target')
    let unrelated = ($fixture | path join 'unrelated')
    mkdir $target $unrelated
    mut owned = []
    let outcome = (try {
        let outside = (spawn-holder $unrelated /bin/sleep)
        $owned = ($owned | append $outside)
        let normal = (spawn-holder $target /bin/sleep)
        $owned = ($owned | append $normal)
        assert ($normal.pid in (project-holders [$target] | get pid))
        release-project-holders [$target]
        assert (not (alive $normal))
        assert (alive $outside)

        let stubborn = (spawn-holder $target /bin/sleep --ignore-term)
        $owned = ($owned | append $stubborn)
        release-project-holders [$target]
        assert (not (alive $stubborn))

        # Launch a real Nu process from the fixture to test self/ancestor safety.
        let innocent = (spawn-holder $target /bin/sleep)
        $owned = ($owned | append $innocent)
        let module = ($env.FILE_PWD | path join 'workspace-processes.nu')
        let command = 'use ' + ($module | to nuon) + ' release-project-holders; release-project-holders [' + ($target | to nuon) + ']'
        let protected = (^sh -c 'cd "$1" || exit; exec "$2" -c "$3"' fixture $target $nu.current-exe $command | complete)
        assert ($protected.exit_code != 0)
        assert ($protected.stderr | str contains 'Protected process')
        assert (alive $innocent)

        # A synthetic Zed-named sleeper, not the user's editor.
        let zed = ($fixture | path join 'zed-editor')
        ^ln -s /bin/sleep $zed
        let editor = (spawn-holder $target $zed)
        $owned = ($owned | append $editor)
        let refused = (try { release-project-holders [$target]; false } catch {|problem| $problem.msg | str contains 'Protected process' })
        assert $refused
        assert (alive $editor)
        assert (alive $innocent)
        let switch = ($env.FILE_PWD | path join 'workspace-pilot-switch.nu')
        let invalid = (^nu $switch --verify-only --kill | complete)
        assert ($invalid.exit_code != 0)
        assert ($invalid.stderr | str contains 'verification-only never terminates')
        {passed: true, message: ''}
    } catch {|problem| {passed: false, message: ($problem.rendered? | default $problem.msg)} })
    for snapshot in $owned {
        if (alive $snapshot) { ^kill --signal KILL -- ($snapshot.pid | into string) | complete | ignore }
    }
    rm --recursive $fixture
    if not $outcome.passed { error make {msg: $outcome.message} }
    print 'PASS: project-only TERM/KILL cleanup, unrelated process survival, helper and Zed protection with no partial signalling.'
}
