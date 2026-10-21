#!/usr/bin/env nu
# Run with attr's setfattr on PATH, e.g. nix shell nixpkgs#attr --command nu ...
use std/assert
use workspace-rsync.nu XATTR_FILTERS

def checked [program: string, arguments: list<string>] {
    let result = (run-external $program ...$arguments | complete)
    if $result.exit_code != 0 { error make {msg: $'($program): ($result.stderr)'} }
    $result.stdout | str trim
}

def main [] {
    let fixture = (checked mktemp ['-d' '/tmp/workspace-xattr-test.XXXXXX'])
    let source = ($fixture | path join 'source')
    let destination = ($fixture | path join 'destination')
    mkdir $source $destination
    let outcome = (try {
        'synthetic file' | save ($source | path join 'file')
        checked setfacl ['-m' 'g:workspace:rw-' ($source | path join 'file')] | ignore
        checked setfattr ['-n' 'user.workspace-proof' '-v' 'original' ($source | path join 'file')] | ignore
        checked rsync ['-aHAX' ...$XATTR_FILTERS '--' $'($source)/' $'($destination)/'] | ignore
        let source_acl = (checked getfacl ['-cn' ($source | path join 'file')])
        let copied_acl = (checked getfacl ['-cn' ($destination | path join 'file')])
        assert equal $source_acl $copied_acl
        assert ((checked getfattr ['--only-values' '-n' 'user.workspace-proof' ($destination | path join 'file')]) == 'original')
        checked setfattr ['-n' 'user.workspace-proof' '-v' 'changed' ($destination | path join 'file')] | ignore
        let differences = (checked rsync ['-aHAXnc' ...$XATTR_FILTERS '--out-format=%i %n' '--' $'($source)/' $'($destination)/'])
        assert ($differences | str contains '.f........x file')
        checked rsync ['-aHAX' ...$XATTR_FILTERS '--' $'($source)/' $'($destination)/'] | ignore
        let repaired = (checked rsync ['-aHAXnc' ...$XATTR_FILTERS '--out-format=%i %n' '--' $'($source)/' $'($destination)/'])
        assert ($repaired | is-empty)
        {passed: true, message: ''}
    } catch {|problem| {passed: false, message: $problem.msg} })
    rm --recursive $fixture
    if not $outcome.passed { error make {msg: $outcome.message} }
    print 'PASS: POSIX ACLs and user xattrs preserved; xattr corruption detected and repaired.'
    print 'Root-only XFS internal-attribute behavior still requires the host verification command.'
}
