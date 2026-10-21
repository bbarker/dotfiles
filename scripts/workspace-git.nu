# Independent ordinary host clone. Automatic fetches never change its working tree.
export def checked [program: string, arguments: list<string>] {
    # Trust only the explicitly supplied repository path, never a global wildcard.
    let arguments = if $program == 'git' and ('-C' in $arguments) {
        let position = ($arguments | enumerate | where item == '-C' | first | get index)
        ['-c' $'safe.directory=($arguments | get ($position + 1))'] | append $arguments
    } else { $arguments }
    let result = (run-external $program ...$arguments | complete)
    if $result.exit_code != 0 {
        error make {msg: $'($program) failed: ($result.stderr | str trim)'}
    }
    $result.stdout | str trim
}

def refs-of [repository: path] {
    let refs = (checked git ['-C' $repository 'for-each-ref' '--format=%(refname) %(objectname)' 'refs/heads' 'refs/tags'])
    let head = (checked git ['-C' $repository 'rev-parse' '--verify' 'HEAD^{commit}'])
    {refs: $refs, head: $head}
}

def source-upload-command [git_directory: path] {
    # Git 2.43 clears config when launching local upload-pack. Put the exact
    # source trust directly on that child command. Git runs this via a shell,
    # so quote every word, including paths containing apostrophes or spaces.
    ['git' '-c' $'safe.directory=($git_directory)' 'upload-pack']
    | each {|word| "'" + ($word | str replace --all "'" "'\\''") + "'" }
    | str join ' '
}

export def backup-repository [source: path, destination: path] {
    let source = ($source | path expand --strict)
    let destination = ($destination | path expand)
    if ($destination == $source) or ($destination | str starts-with $'($source)/') {
        error make {msg: 'Backup must be independent and outside the source repository.'}
    }
    # Git 2.43's upload-pack checks the Git directory itself when clone/fetch
    # launches it for a foreign-owned local source. Trust both exact paths for
    # this invocation; never add a global safe.directory or wildcard.
    let source_git = (checked git ['-C' $source 'rev-parse' '--absolute-git-dir'] | path expand --strict)
    let upload = (source-upload-command $source_git)
    let before = (refs-of $source)
    if not ($destination | path exists) {
        checked git ['-c' $'safe.directory=($source)' 'clone' '--upload-pack' $upload '--no-local' '--config' 'core.sharedRepository=group' $source $destination] | ignore
    }
    if (checked git ['-C' $destination 'rev-parse' '--is-bare-repository']) != 'false' {
        error make {msg: 'Host backup must be an ordinary clone. Preserve the old bare backup separately before replacing it.'}
    }
    let common = (checked git ['-C' $destination 'rev-parse' '--path-format=absolute' '--git-common-dir'])
    if ($common | path expand) != ($destination | path join '.git') {
        error make {msg: 'Host backup cannot be a linked worktree or use an external Git directory.'}
    }
    if ($common | path join 'objects' 'info' 'alternates' | path exists) {
        error make {msg: 'Host backup uses borrowed objects; create an independent clone with --no-local.'}
    }
    checked git ['-C' $destination 'config' 'core.sharedRepository' 'group'] | ignore
    # A clone starts with symbolic origin/HEAD. Make it a direct latest-source-HEAD
    # ref so fetching a detached source HEAD cannot overwrite origin/main through it.
    let previous = (^git -c $'safe.directory=($destination)' -C $destination rev-parse --verify refs/remotes/origin/HEAD | complete)
    if $previous.exit_code == 0 {
        checked git ['-C' $destination 'update-ref' '--no-deref' 'refs/remotes/origin/HEAD' ($previous.stdout | str trim)] | ignore
    }
    checked git [
        '-C' $destination '-c' 'fetch.prune=false' '-c' 'fetch.pruneTags=false'
        'fetch' '--upload-pack' $upload '--atomic' '--no-tags' '--no-prune' '--no-prune-tags'
        '--no-recurse-submodules' $source
        '+refs/heads/*:refs/remotes/origin/*'
        '+refs/tags/*:refs/tags/*'
        '+HEAD:refs/remotes/origin/HEAD'
    ] | ignore
    if (refs-of $source) != $before {
        error make {msg: 'Source refs changed during backup. Finish writers and retry; backup not confirmed.'}
    }
    let expected = ($before.refs | lines | each {|line|
        $line | str replace 'refs/heads/' 'refs/remotes/origin/'
    } | append $'refs/remotes/origin/HEAD ($before.head)')
    for entry in $expected {
        let parts = ($entry | split row ' ')
        if (checked git ['-C' $destination 'show-ref' '--verify' '--hash' $parts.0]) != $parts.1 {
            error make {msg: 'Fetched refs do not match the source; backup not confirmed.'}
        }
    }
    checked git ['-C' $destination 'fsck' '--connectivity-only' '--no-dangling'] | ignore
    {repository: $destination, head: $before.head}
}
