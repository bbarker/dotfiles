use std assert
use workspace-git.nu [checked backup-repository]

def main [] {
    let temporary = (mktemp --directory | str trim)
    let source = ($temporary | path join 'source')
    let backup = ($temporary | path join 'source-Host')
    checked git ['init' '--initial-branch=main' $source] | ignore
    checked git ['-C' $source 'config' 'user.name' 'Workspace test'] | ignore
    checked git ['-C' $source 'config' 'user.email' 'workspace-test@example.invalid'] | ignore
    'one' | save ($source | path join 'tracked.txt')
    checked git ['-C' $source 'add' 'tracked.txt'] | ignore
    checked git ['-C' $source 'commit' '-m' 'first'] | ignore
    checked git ['-C' $source 'branch' 'later-deleted'] | ignore
    checked git ['-C' $source 'tag' 'v1'] | ignore
    backup-repository $source $backup | ignore
    assert equal (checked git ['-C' $backup 'rev-parse' '--is-bare-repository']) 'false'
    assert equal (open --raw ($backup | path join 'tracked.txt')) 'one'
    assert equal (checked git ['-C' $backup 'config' '--get' 'core.sharedRepository']) 'group'
    assert equal (checked git ['-C' $backup 'for-each-ref' 'refs/workspace-backups']) ''
    let initial_host_head = (checked git ['-C' $backup 'rev-parse' 'HEAD'])
    'host edit' | save --force ($backup | path join 'tracked.txt')
    'host untracked' | save ($backup | path join 'local.txt')
    checked git ['-C' $backup 'config' 'fetch.prune' 'true'] | ignore
    checked git ['-C' $backup 'config' 'fetch.pruneTags' 'true'] | ignore
    checked git ['-C' $backup 'config' 'remote.origin.prune' 'true'] | ignore
    'two' | save --force ($source | path join 'tracked.txt')
    checked git ['-C' $source 'commit' '-am' 'second'] | ignore
    checked git ['-C' $source 'tag' '--force' 'v1'] | ignore
    checked git ['-C' $source 'branch' '-D' 'later-deleted'] | ignore
    let branch_tip = (checked git ['-C' $source 'rev-parse' 'HEAD'])
    checked git ['-C' $source 'checkout' '--detach'] | ignore
    'three' | save --force ($source | path join 'tracked.txt')
    checked git ['-C' $source 'commit' '-am' 'detached commit'] | ignore
    let latest = (checked git ['-C' $source 'rev-parse' 'HEAD'])
    'source edit' | save --force ($source | path join 'tracked.txt')
    backup-repository $source $backup | ignore
    assert equal (checked git ['-C' $backup 'rev-parse' 'refs/remotes/origin/main']) $branch_tip
    assert equal (checked git ['-C' $backup 'rev-parse' 'refs/remotes/origin/HEAD']) $latest
    assert equal (checked git ['-C' $backup 'rev-parse' 'refs/tags/v1']) $branch_tip
    assert equal (checked git ['-C' $backup 'rev-parse' 'refs/remotes/origin/later-deleted']) $initial_host_head
    assert equal (checked git ['-C' $backup 'rev-parse' 'HEAD']) $initial_host_head
    assert equal (open --raw ($backup | path join 'tracked.txt')) 'host edit'
    assert equal (open --raw ($backup | path join 'local.txt')) 'host untracked'
    assert equal (open --raw ($source | path join 'tracked.txt')) 'source edit'
    assert equal (checked git ['-C' $backup 'for-each-ref' 'refs/workspace-backups']) ''
    let borrowed = ($temporary | path join 'borrowed')
    checked git ['clone' '--shared' $source $borrowed] | ignore
    assert (try { backup-repository $source $borrowed | ignore; false } catch { true }) 'Reject borrowed object storage.'
    rm --recursive $source
    checked git ['-C' $backup 'fsck' '--connectivity-only' '--no-dangling'] | ignore
    let restored = ($temporary | path join 'restored')
    checked git ['clone' '--no-local' $backup $restored] | ignore
    checked git ['-C' $restored 'fetch' $backup 'refs/remotes/origin/main'] | ignore
    checked git ['-C' $restored 'checkout' '--detach' 'FETCH_HEAD'] | ignore
    assert equal (open --raw ($restored | path join 'tracked.txt')) 'two'
    checked git ['-C' $restored 'fetch' $backup 'refs/remotes/origin/HEAD'] | ignore
    checked git ['-C' $restored 'checkout' '--detach' 'FETCH_HEAD'] | ignore
    assert equal (open --raw ($restored | path join 'tracked.txt')) 'three'
    rm --recursive $temporary
    print 'PASS: ordinary independent clone, automatic fetch contract, no pruning, retagging, detached HEAD, working-copy preservation and disconnected restore.'
}
