# Resolve one explicitly selected migration without touching other projects.
export def migration-project [name: string, --config: path] {
    let file = ($config | default ($env.FILE_PWD | path join '..' 'workspace-drive.toml'))
    let manifest = (open $file)
    let matches = ($manifest.projects | where name == $name)
    if ($matches | length) != 1 { error make {msg: 'Expected exactly one matching project in the drive manifest.'} }
    let project = ($matches | first)
    if not ($project.enabled? | default true) { error make {msg: 'Selected project is disabled in the manifest.'} }
    if not ($name =~ '^[A-Za-z0-9_-]+$') { error make {msg: 'Invalid migration project name.'} }
    let source = $'/var/workspace/($name)'
    if $project.target != $source or $project.directory != $'projects/($name)' or $project.backup != $'($source)-Host' {
        error make {msg: 'Migration requires matching project name, canonical target, SSD directory and independent host backup.'}
    }
    {config: $manifest, project: $project, source: $source, rollback: $'($source)-PreSSD'}
}
