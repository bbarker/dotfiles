use std/assert
use zed-holders.nu [zed-projects broken-directories watches]

def main [] {
    let fixture = (^mktemp -d /tmp/zed-holders-test.XXXXXX | str trim)
    let kept = ($fixture | path join 'kept')
    let removed = ($fixture | path join 'removed')
    let state = ($fixture | path join 'state')
    mkdir $kept $removed $state
    mut sleeper = 0
    let outcome = (try {
        # A state database shaped like Zed's: one window in this session with a
        # folder that is gone, one from an older session that must be ignored.
        let db = ($state | path join 'db.sqlite')
        [[key value]; [session_id current]] | into sqlite $db --table-name kv_store
        [[workspace_id paths session_id remote_connection_id];
            [1 ($kept + "\n" + $removed) current '']
            [2 '/elsewhere' older '']
        ] | into sqlite $db --table-name workspaces
        open $db | query db "update workspaces set remote_connection_id = null" | ignore
        rm -r $removed
        let projects = (zed-projects $state)
        assert equal ($projects | get folder) [$kept $removed]
        assert equal ($projects | get state) ['ok' 'No such file or directory']

        # A disposable process standing in a directory that is then deleted.
        let spawned = (^sh -c 'cd "$1" || exit; sleep 60 </dev/null >/dev/null 2>&1 & printf "%s\n" "$!"' fixture $kept | complete)
        $sleeper = ($spawned.stdout | str trim | into int)
        sleep 100ms
        assert (broken-directories [$sleeper] | is-empty)
        rm -r $kept
        let broken = (broken-directories [$sleeper])
        assert equal ($broken | get link) ['cwd']
        assert equal ($broken | get problem) ['deleted']
        assert ($broken.0.target | str ends-with ' (deleted)')
        assert (watches [$sleeper] | is-empty)
        null
    } catch {|problem| $problem })
    if $sleeper > 0 { ^kill $sleeper | complete | ignore }
    rm -rf $fixture
    if $outcome != null { error make {msg: $outcome.msg} }
    print 'zed-holders tests passed.'
}
