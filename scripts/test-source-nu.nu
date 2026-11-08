#!/usr/bin/env nu
use std assert

def read-file [script: path, file: path, ...flags: string] {
    let result = (^$nu.current-exe --no-config-file $script ...$flags $file | complete)
    assert equal $result.exit_code 0 $result.stderr
    $result.stdout
}

def main [] {
    let script = ($env.FILE_PWD | path dirname | path join '.config' 'home-manager' 'scripts' 'source_nu')
    let temporary = (mktemp --directory | str trim)
    let file = ($temporary | path join 'example.env')
    [
        '# a comment'
        'PLAIN=one'
        'export EXPORTED="two words"'
        "SINGLE='it''s \$literal'"
        'FROM_HOME="$HOME/x"'
        'MULTI="line one'
        'line two"'
        ''
        $"HOME=($env.HOME)"
    ] | str join (char nl) | save $file

    let variables = (read-file $script $file | from json)
    assert equal $variables.PLAIN 'one'
    assert equal $variables.EXPORTED 'two words'
    assert equal $variables.SINGLE "its $literal"
    assert equal $variables.FROM_HOME ($env.HOME | path join 'x')
    assert equal $variables.MULTI $"line one(char nl)line two"
    # Set to what bash already had, so it is not the file's doing.
    assert ('HOME' not-in ($variables | columns))
    assert ('SHLVL' not-in ($variables | columns))

    let names = (read-file $script $file '--names' | lines)
    assert equal ($names | sort) [EXPORTED FROM_HOME MULTI PLAIN SINGLE]

    let broken = ($temporary | path join 'broken.env')
    'X="unterminated' | save $broken
    let refused = (^$nu.current-exe --no-config-file $script $broken | complete)
    assert not equal $refused.exit_code 0

    rm -r $temporary
    print 'source_nu: ok'
}
