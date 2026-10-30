#!/usr/bin/env nu
use std assert

def run-key [script: path, ...arguments: string] {
    let result = (^$nu.current-exe --no-config-file $script ...$arguments | complete)
    $result
}

def permissions [file: path] { ^stat -c '%a' -- $file | str trim }

def scheduled [cron: path] {
    open --raw $cron | lines | where {|row| $row | str contains '# unlock-key:' }
}

def timer-arguments [cron: path] {
    scheduled $cron | first | parse --regex "'(?<deadline>[0-9]+)' '(?<identity>[0-9:]+)' '(?<token>[a-f0-9-]+)' #" | first
}

def main [] {
    let script = ($env.FILE_PWD | path join 'unlock-key.nu')
    let temporary = (^mktemp -d | str trim)
    let fixture = ($temporary | path join "dummy ' key % $(touch SHOULD-NOT-EXIST)")
    let cron = ($temporary | path join 'crontab.txt')
    let mock = ($temporary | path join 'crontab')
    let group = (^id -gn | str trim)
    let mock_source = '#!/usr/bin/env -S nu --no-config-file --stdin
def main [file?: string, --list (-l)] {
    let input = $in
    if ($env.MOCK_CRON_FAIL? | default "") == "1" { print --stderr "cron unavailable"; exit 2 }
    if $list {
        if ($env.MOCK_CRON | path exists) { open --raw $env.MOCK_CRON | print --no-newline } else {
            print --stderr "no crontab for fixture"; exit 1
        }
    } else if $file == "-" { $input | save --force $env.MOCK_CRON } else { exit 3 }
}
'
    $mock_source | save $mock
    ^chmod 700 $mock
    'harmless fixture' | save $fixture
    ^chmod 600 $fixture
    try {
        with-env {PATH: ([$temporary] | append $env.PATH), MOCK_CRON: $cron} {
            assert equal (run-key $script $fixture '--group' $group '--no-timer').exit_code 0
            assert equal (permissions $fixture) '640'
            assert equal (run-key $script $fixture '--relock').exit_code 0
            assert equal (permissions $fixture) '600'

            let unrelated = '# preserved unrelated cron comment'
            $unrelated | save --force $cron
            let before = (date now | into int)
            assert equal (run-key $script $fixture '--group' $group).exit_code 0
            let first_timer = (timer-arguments $cron)
            let delta = (($first_timer.deadline | into int) - $before)
            assert ($delta >= (2hr | into int) and $delta < ((2hr + 10sec) | into int))
            assert equal (permissions $fixture) '640'
            assert equal (scheduled $cron | length) 1
            assert equal (run-key $script 'expire' $fixture $first_timer.deadline $first_timer.identity $first_timer.token).exit_code 0
            assert equal (permissions $fixture) '640' # Not due yet.

            assert equal (run-key $script $fixture '--group' $group '--after' '30min').exit_code 0
            assert equal (scheduled $cron | length) 1
            let second_timer = (timer-arguments $cron)
            assert ($second_timer.token != $first_timer.token)
            assert equal (run-key $script 'expire' $fixture '0' $first_timer.identity $first_timer.token).exit_code 0
            assert equal (permissions $fixture) '640' # Superseded timer cannot relock.
            assert equal (run-key $script 'expire' $fixture '0' $second_timer.identity $second_timer.token).exit_code 0
            assert equal (permissions $fixture) '600'
            assert equal (scheduled $cron | length) 0
            assert equal (open --raw $cron | str trim) $unrelated

            assert equal (run-key $script $fixture '--group' $group).exit_code 0
            assert equal (run-key $script $fixture '--relock').exit_code 0
            assert equal (scheduled $cron | length) 0

            # Execute the actual generated shell command, undoing cron's percent escape.
            assert equal (run-key $script $fixture '--group' $group '--after' '1ns').exit_code 0
            let command = (scheduled $cron | first | str substring 10.. | str replace --all '\%' '%')
            let fired = (^sh -c $command | complete)
            assert equal $fired.exit_code 0
            assert equal (permissions $fixture) '600'
            assert equal (scheduled $cron | length) 0

            # A new file at the old pathname must not inherit the old file's timer.
            assert equal (run-key $script $fixture '--group' $group).exit_code 0
            let old_timer = (timer-arguments $cron)
            let moved = ($temporary | path join 'original')
            mv $fixture $moved
            'replacement' | save $fixture
            ^chmod 640 $fixture
            assert equal (run-key $script 'expire' $fixture '0' $old_timer.identity $old_timer.token).exit_code 0
            assert equal (permissions $fixture) '640'
            assert equal (scheduled $cron | length) 0
            assert equal (run-key $script $moved '--relock').exit_code 0

            assert equal (run-key $script $fixture '--relock').exit_code 0
            with-env {MOCK_CRON_FAIL: '1'} {
                assert ((run-key $script $fixture '--group' $group).exit_code != 0)
                assert equal (permissions $fixture) '600'
                assert equal (run-key $script $fixture '--group' $group '--no-timer').exit_code 0
                assert equal (permissions $fixture) '640'
                assert equal (run-key $script $fixture '--relock').exit_code 0
                assert equal (permissions $fixture) '600'
            }

            ^setfacl -m $'u:(^id -u | str trim):r' -- $fixture
            assert equal (run-key $script $fixture '--group' $group '--no-timer').exit_code 0
            assert not ((^getfacl -cpn -- $fixture) =~ '(?m)^user:[^:]+:')
            assert equal (run-key $script $fixture '--relock').exit_code 0
            assert equal (permissions $fixture) '600'

            let link = ($temporary | path join 'symlink')
            ^ln -s -- $fixture $link
            assert ((run-key $script $link '--group' $group '--no-timer').exit_code != 0)
            assert ((run-key $script $temporary '--group' $group '--no-timer').exit_code != 0)
            assert ((run-key $script '/proc/version' '--relock').exit_code != 0)
            assert ((run-key $script $fixture '--group' 'unlock-key-nonexistent-group' '--no-timer').exit_code != 0)
            assert ((run-key $script $fixture '--group' $group '--after' '0sec').exit_code != 0)
            assert equal (permissions $fixture) '600'
            assert equal (open --raw $fixture) 'replacement'
            assert not ('SHOULD-NOT-EXIST' | path exists)
            print 'PASS: modes, ACL cleanup, timer defaults, early/expired/stale timers, quoting, replacement protection, manual cancellation, cron failure, and invalid targets'
        }
    } catch {|failure|
        print --stderr ($failure | to nuon)
        rm --recursive $temporary
        error make {msg: $failure.msg}
    }
    rm --recursive $temporary
}
