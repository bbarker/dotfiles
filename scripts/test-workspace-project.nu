use std/assert
use workspace-project.nu migration-project

def main [] {
    let file = ($env.FILE_PWD | path join '..' 'workspace-drive.toml')
    let app = (migration-project 'AlygnApp' --config $file)
    let pilot = (migration-project 'shoggothox' --config $file)
    assert equal $app.source '/var/workspace/AlygnApp'
    assert equal $app.rollback '/var/workspace/AlygnApp-PreSSD'
    assert equal $app.project.directory 'projects/AlygnApp'
    assert equal $pilot.source '/var/workspace/shoggothox'
    let scratch = (mktemp --directory | str trim)
    let fixture = ($scratch | path join 'manifest.toml')
    let config = (open $file)
    let disabled = ($app.project | upsert enabled false)
    $config | upsert projects [$disabled $pilot.project] | to toml | save $fixture
    assert (try { migration-project 'AlygnApp' --config $fixture | ignore; false } catch { true })
    let invalid = ($app.project | upsert target '/var/workspace/shoggothox')
    $config | upsert projects [$invalid $pilot.project] | to toml | save --force $fixture
    assert (try { migration-project 'AlygnApp' --config $fixture | ignore; false } catch { true })
    $config | upsert projects [$app.project $app.project] | to toml | save --force $fixture
    assert (try { migration-project 'AlygnApp' --config $fixture | ignore; false } catch { true })
    let cli = ($env.FILE_PWD | path join 'workspace-drive.nu')
    let missing = (^nu $cli backup --project nonexistent | complete)
    assert ($missing.exit_code != 0)
    assert ($missing.stderr | str contains 'Expected exactly one enabled backup project')
    let refused = (^nu $cli unmount --project AlygnApp | complete)
    assert ($refused.exit_code != 0)
    assert ($refused.stderr | str contains 'supported only for backup')
    rm --recursive $scratch
    print 'PASS: explicit migration selection, isolated paths, disabled/duplicate/mismatched project refusal and backup-only selection.'
}
