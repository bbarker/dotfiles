#!/usr/bin/env nu
use std/assert
use workspace-git.nu [checked backup-repository]

def main [] {
    let temporary = (mktemp --directory | str trim)
    let source = ($temporary | path join "source with ' apostrophe")
    let backup = ($temporary | path join 'source-Host')
    let outcome = (try {
        checked git ['init' '--initial-branch=main' $source] | ignore
        checked git ['-C' $source 'config' 'user.name' 'Workspace ownership test'] | ignore
        checked git ['-C' $source 'config' 'user.email' 'workspace-test@example.invalid'] | ignore
        'first' | save ($source | path join 'tracked')
        checked git ['-C' $source 'add' 'tracked'] | ignore
        checked git ['-C' $source 'commit' '-m' 'initial'] | ignore
        # Git's own test hook reproduces foreign ownership without root/chown.
        with-env {GIT_TEST_ASSUME_DIFFERENT_OWNER: '1'} {
            backup-repository $source $backup | ignore
            'second' | save --force ($source | path join 'tracked')
            checked git ['-C' $source 'commit' '-am' 'next'] | ignore
            let expected = (checked git ['-C' $source 'rev-parse' 'HEAD'])
            backup-repository $source $backup | ignore
            assert equal (checked git ['-C' $backup 'rev-parse' 'refs/remotes/origin/HEAD']) $expected
            # Trust must not leak into global configuration or unrelated commands.
            let untrusted = (^git -C $source rev-parse HEAD | complete)
            assert ($untrusted.exit_code != 0)
            assert ($untrusted.stderr | str contains 'dubious ownership')
        }
        {passed: true, message: ''}
    } catch {|problem| {passed: false, message: $problem.msg} })
    rm --recursive $temporary
    if not $outcome.passed { error make {msg: $outcome.message} }
    print 'PASS: foreign-owner clone/fetch succeeds with command-scoped trust; unrelated Git commands remain untrusted.'
}
