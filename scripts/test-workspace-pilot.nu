use std assert

def selected [script: path, manifest: path] {
    let command = $"source ($script | to nuon); load-config ($manifest | to nuon) | get projects.name | to json"
    ^nu --commands $command | from json
}

def main [] {
    let script = ($env.FILE_PWD | path join 'workspace-drive.nu')
    let scratch = (mktemp --directory | str trim)
    let file = ($scratch | path join 'pilot.toml')
    let config = (open ($env.FILE_PWD | path join '..' 'workspace-drive.toml'))
    let later = ($config.projects | where name == 'AlygnApp' | first | upsert enabled false)
    let pilot = {name: 'shoggothox', enabled: true, directory: 'projects/shoggothox', target: '/var/workspace/shoggothox', backup: '/var/workspace/shoggothox-Host'}
    $config | upsert projects [$later $pilot] | to toml | save $file
    assert equal (selected $script $file) ['shoggothox']
    # Old manifests without a flag continue selecting their listed projects.
    $config | upsert projects [($pilot | reject enabled)] | to toml | save --force $file
    assert equal (selected $script $file) ['shoggothox']
    # Disabling everything must not permit an accidental raw-volume unmount.
    $config | upsert projects [$later ($pilot | upsert enabled false)] | to toml | save --force $file
    let refused = (^nu $script unmount --config $file --quiescent | complete)
    assert ($refused.exit_code != 0)
    assert ($refused.stderr | str contains 'No projects enabled')
    rm --recursive $scratch
    print 'PASS: pilot selection, deferred Alygn retained, legacy defaults and no-project lifecycle refusal.'
}
